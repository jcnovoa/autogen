#!/bin/bash

# AutoGen Studio ECS Fargate Deployment
# Account: 992257105959, Region: us-east-1

set -e

# Configuration
AWS_ACCOUNT_ID="992257105959"
AWS_REGION="us-east-1"
ECR_REPOSITORY="autogen-studio"
CLUSTER_NAME="autogen-studio-cluster"
SERVICE_NAME="autogen-studio-service"
TASK_DEFINITION="autogen-studio-task"
DOMAIN_NAME="autogen.successkpis.world"
HOSTED_ZONE_ID="Z01161512I4PAKIUL4YRN"

echo "🚀 AutoGen Studio ECS Fargate Deployment"
echo "========================================"
echo "Account: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "Domain: $DOMAIN_NAME"
echo ""

# Step 1: Create ECS Cluster
echo "🏗️ Creating ECS Cluster..."
aws ecs create-cluster \
    --cluster-name $CLUSTER_NAME \
    --capacity-providers FARGATE \
    --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
    --region $AWS_REGION || echo "Cluster may already exist"

# Step 2: Create Application Load Balancer
echo "🔗 Creating Application Load Balancer..."

# Get default VPC
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --region $AWS_REGION \
    --query 'Vpcs[0].VpcId' \
    --output text)

# Get subnets
SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $AWS_REGION \
    --query 'Subnets[*].SubnetId' \
    --output text | tr '\t' ',')

# Create security group for ALB
ALB_SG_ID=$(aws ec2 create-security-group \
    --group-name autogen-studio-alb-sg \
    --description "Security group for AutoGen Studio ALB" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' \
    --output text 2>/dev/null || \
    aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=autogen-studio-alb-sg" \
        --region $AWS_REGION \
        --query 'SecurityGroups[0].GroupId' \
        --output text)

# Allow HTTP and HTTPS traffic
aws ec2 authorize-security-group-ingress \
    --group-id $ALB_SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION 2>/dev/null || echo "HTTP rule may already exist"

aws ec2 authorize-security-group-ingress \
    --group-id $ALB_SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION 2>/dev/null || echo "HTTPS rule may already exist"

# Create ALB
ALB_ARN=$(aws elbv2 create-load-balancer \
    --name autogen-studio-alb \
    --subnets $(echo $SUBNET_IDS | tr ',' ' ') \
    --security-groups $ALB_SG_ID \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text 2>/dev/null || \
    aws elbv2 describe-load-balancers \
        --names autogen-studio-alb \
        --region $AWS_REGION \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns $ALB_ARN \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo "✅ ALB created: $ALB_DNS"

# Step 3: Create Target Group
echo "🎯 Creating Target Group..."
TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
    --name autogen-studio-tg \
    --protocol HTTP \
    --port 8080 \
    --vpc-id $VPC_ID \
    --target-type ip \
    --health-check-path /docs \
    --region $AWS_REGION \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || \
    aws elbv2 describe-target-groups \
        --names autogen-studio-tg \
        --region $AWS_REGION \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)

# Step 4: Create ALB Listener
echo "👂 Creating ALB Listener..."
aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
    --region $AWS_REGION 2>/dev/null || echo "Listener may already exist"

# Step 5: Create ECS Task Definition
echo "📋 Creating ECS Task Definition..."
cat > task-definition.json << EOF
{
  "family": "$TASK_DEFINITION",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "autogen-studio",
      "image": "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:latest",
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "DATABASE_URI",
          "value": "postgresql://autogen_admin:AutoGenStudio2024!SecurePass@autogen-studio-db.chgrjdh8i2jz.us-east-1.rds.amazonaws.com:5432/postgres"
        },
        {
          "name": "PORT",
          "value": "8080"
        },
        {
          "name": "HOST",
          "value": "0.0.0.0"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/autogen-studio",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8080/docs || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF

# Create CloudWatch Log Group
aws logs create-log-group \
    --log-group-name /ecs/autogen-studio \
    --region $AWS_REGION 2>/dev/null || echo "Log group may already exist"

# Register task definition
aws ecs register-task-definition \
    --cli-input-json file://task-definition.json \
    --region $AWS_REGION

# Step 6: Create ECS Service
echo "🚀 Creating ECS Service..."

# Create security group for ECS tasks
ECS_SG_ID=$(aws ec2 create-security-group \
    --group-name autogen-studio-ecs-sg \
    --description "Security group for AutoGen Studio ECS tasks" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' \
    --output text 2>/dev/null || \
    aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=autogen-studio-ecs-sg" \
        --region $AWS_REGION \
        --query 'SecurityGroups[0].GroupId' \
        --output text)

# Allow traffic from ALB
aws ec2 authorize-security-group-ingress \
    --group-id $ECS_SG_ID \
    --protocol tcp \
    --port 8080 \
    --source-group $ALB_SG_ID \
    --region $AWS_REGION 2>/dev/null || echo "ECS rule may already exist"

# Create ECS service
aws ecs create-service \
    --cluster $CLUSTER_NAME \
    --service-name $SERVICE_NAME \
    --task-definition $TASK_DEFINITION \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$ECS_SG_ID],assignPublicIp=ENABLED}" \
    --load-balancers targetGroupArn=$TARGET_GROUP_ARN,containerName=autogen-studio,containerPort=8080 \
    --region $AWS_REGION 2>/dev/null || echo "Service may already exist"

# Step 7: Update DNS to point to ALB
echo "🌐 Updating DNS to point to ALB..."
cat > dns-change-batch-alb.json << EOF
{
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "$DOMAIN_NAME",
            "Type": "CNAME",
            "TTL": 300,
            "ResourceRecords": [{"Value": "$ALB_DNS"}]
        }
    }]
}
EOF

aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch file://dns-change-batch-alb.json

echo ""
echo "🎉 ECS Fargate Deployment Complete!"
echo "==================================="
echo ""
echo "📋 Deployment Summary:"
echo "   • ECS Cluster: $CLUSTER_NAME"
echo "   • ECS Service: $SERVICE_NAME"
echo "   • Load Balancer: $ALB_DNS"
echo "   • Custom Domain: https://$DOMAIN_NAME"
echo ""
echo "🔧 Next Steps:"
echo "   1. Wait 5-10 minutes for ECS service to start"
echo "   2. Test: http://$ALB_DNS"
echo "   3. Test: https://$DOMAIN_NAME (after DNS propagation)"
echo "   4. Configure SSL certificate for HTTPS"
echo ""

# Cleanup
rm -f task-definition.json dns-change-batch-alb.json

echo "📄 Deployment completed successfully!"
