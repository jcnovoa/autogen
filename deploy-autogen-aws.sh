#!/bin/bash

# AutoGen Studio AWS Deployment Script
# Optimized for Account: 992257105959, Region: us-east-1
# Domain: autogen.successkpis.world

set -e

# Configuration
AWS_ACCOUNT_ID="992257105959"
AWS_REGION="us-east-1"
ECR_REPOSITORY="autogen-studio"
APP_NAME="autogen-studio"
DOMAIN_NAME="autogen.successkpis.world"
HOSTED_ZONE_ID="Z01161512I4PAKIUL4YRN"
DB_INSTANCE_ID="autogen-studio-db"

echo "🚀 AutoGen Studio AWS Deployment"
echo "=================================="
echo "Account: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "Domain: $DOMAIN_NAME"
echo "Hosted Zone: $HOSTED_ZONE_ID"
echo ""

# Verify AWS credentials
echo "🔐 Verifying AWS credentials..."
aws sts get-caller-identity --region $AWS_REGION > /dev/null
echo "✅ AWS credentials verified"
echo ""

# Step 1: Create ECR Repository
echo "📦 Setting up ECR Repository..."
if aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION &>/dev/null; then
    echo "✅ ECR Repository already exists"
else
    aws ecr create-repository \
        --repository-name $ECR_REPOSITORY \
        --region $AWS_REGION \
        --image-scanning-configuration scanOnPush=true
    echo "✅ ECR Repository created"
fi
echo ""

# Step 2: Build and Push Docker Image
echo "🔨 Building and pushing Docker image..."
echo "Building image..."
docker build -t $ECR_REPOSITORY .

echo "Tagging for ECR..."
docker tag $ECR_REPOSITORY:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:latest

echo "Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

echo "Pushing to ECR..."
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:latest
echo "✅ Docker image pushed successfully"
echo ""

# Step 3: Create RDS Database
echo "🗄️ Setting up PostgreSQL database..."
if aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_ID --region $AWS_REGION &>/dev/null; then
    echo "✅ RDS instance already exists"
    
    # Get existing database info
    DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier $DB_INSTANCE_ID \
        --region $AWS_REGION \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    # Try to get password from Secrets Manager
    if aws secretsmanager describe-secret --secret-id "$APP_NAME/database" --region $AWS_REGION &>/dev/null; then
        DB_PASSWORD=$(aws secretsmanager get-secret-value \
            --secret-id "$APP_NAME/database" \
            --region $AWS_REGION \
            --query 'SecretString' \
            --output text | jq -r '.password')
    else
        echo "⚠️  Database exists but no secret found. Please set DB_PASSWORD environment variable."
        read -s -p "Enter database password: " DB_PASSWORD
        echo ""
    fi
else
    echo "Creating new RDS instance..."
    
    # Generate secure password
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # Create RDS instance
    aws rds create-db-instance \
        --db-instance-identifier $DB_INSTANCE_ID \
        --db-instance-class db.t3.micro \
        --engine postgres \
        --engine-version 15.4 \
        --master-username autogen_admin \
        --master-user-password "$DB_PASSWORD" \
        --allocated-storage 20 \
        --storage-type gp3 \
        --storage-encrypted \
        --backup-retention-period 7 \
        --publicly-accessible \
        --region $AWS_REGION
    
    echo "⏳ Waiting for RDS instance to be available (this may take 5-10 minutes)..."
    aws rds wait db-instance-available --db-instance-identifier $DB_INSTANCE_ID --region $AWS_REGION
    
    # Get RDS endpoint
    DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier $DB_INSTANCE_ID \
        --region $AWS_REGION \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    # Store credentials in Secrets Manager
    echo "🔐 Storing database credentials..."
    aws secretsmanager create-secret \
        --name "$APP_NAME/database" \
        --description "Database credentials for AutoGen Studio" \
        --secret-string "{\"username\":\"autogen_admin\",\"password\":\"$DB_PASSWORD\",\"host\":\"$DB_ENDPOINT\",\"port\":\"5432\",\"dbname\":\"postgres\"}" \
        --region $AWS_REGION
    
    echo "✅ RDS instance created and configured"
fi

DATABASE_URI="postgresql://autogen_admin:$DB_PASSWORD@$DB_ENDPOINT:5432/postgres"
echo "✅ Database ready at: $DB_ENDPOINT"
echo ""

# Step 4: Create App Runner Service
echo "🏃 Setting up App Runner service..."
SERVICE_ARN=$(aws apprunner list-services --region $AWS_REGION --query "ServiceSummaryList[?ServiceName=='$APP_NAME'].ServiceArn" --output text)

if [[ -z "$SERVICE_ARN" ]]; then
    echo "Creating new App Runner service..."
    
    # Create the service
    SERVICE_ARN=$(aws apprunner create-service \
        --service-name $APP_NAME \
        --source-configuration "{
            \"ImageRepository\": {
                \"ImageIdentifier\": \"$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:latest\",
                \"ImageConfiguration\": {
                    \"Port\": \"8080\",
                    \"RuntimeEnvironmentVariables\": {
                        \"DATABASE_URI\": \"$DATABASE_URI\"
                    }
                },
                \"ImageRepositoryType\": \"ECR\"
            }
        }" \
        --instance-configuration "{
            \"Cpu\": \"1 vCPU\",
            \"Memory\": \"2 GB\"
        }" \
        --region $AWS_REGION \
        --query 'Service.ServiceArn' \
        --output text)
    
    echo "⏳ Waiting for App Runner service to be ready..."
    aws apprunner wait service-running --service-arn $SERVICE_ARN --region $AWS_REGION
    echo "✅ App Runner service created"
else
    echo "Updating existing App Runner service..."
    aws apprunner start-deployment --service-arn $SERVICE_ARN --region $AWS_REGION
    echo "⏳ Waiting for deployment to complete..."
    aws apprunner wait service-running --service-arn $SERVICE_ARN --region $AWS_REGION
    echo "✅ App Runner service updated"
fi

# Get App Runner URL
APP_RUNNER_URL=$(aws apprunner describe-service \
    --service-arn $SERVICE_ARN \
    --region $AWS_REGION \
    --query 'Service.ServiceUrl' \
    --output text)

echo "✅ App Runner service ready at: https://$APP_RUNNER_URL"
echo ""

# Step 5: Request SSL Certificate
echo "🔒 Setting up SSL certificate..."
CERT_ARN=$(aws acm list-certificates \
    --region $AWS_REGION \
    --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn" \
    --output text)

if [[ -z "$CERT_ARN" ]]; then
    echo "Requesting new SSL certificate..."
    CERT_ARN=$(aws acm request-certificate \
        --domain-name $DOMAIN_NAME \
        --validation-method DNS \
        --region $AWS_REGION \
        --query 'CertificateArn' \
        --output text)
    
    echo "📋 Certificate ARN: $CERT_ARN"
    echo "⚠️  Certificate validation required - check AWS Console"
else
    echo "✅ SSL certificate already exists: $CERT_ARN"
fi
echo ""

# Step 6: Create DNS Record
echo "🌐 Setting up DNS record..."
cat > /tmp/change-batch.json << EOF
{
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "$DOMAIN_NAME",
            "Type": "CNAME",
            "TTL": 300,
            "ResourceRecords": [{"Value": "$APP_RUNNER_URL"}]
        }
    }]
}
EOF

CHANGE_ID=$(aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch file:///tmp/change-batch.json \
    --query 'ChangeInfo.Id' \
    --output text)

echo "⏳ Waiting for DNS change to propagate..."
aws route53 wait resource-record-sets-changed --id $CHANGE_ID

rm /tmp/change-batch.json
echo "✅ DNS record created/updated"
echo ""

# Step 7: Associate Custom Domain with App Runner
echo "🔗 Associating custom domain with App Runner..."
if aws apprunner list-custom-domains --service-arn $SERVICE_ARN --region $AWS_REGION --query 'CustomDomains[?DomainName==`'$DOMAIN_NAME'`]' --output text | grep -q $DOMAIN_NAME; then
    echo "✅ Custom domain already associated"
else
    echo "Associating custom domain..."
    aws apprunner associate-custom-domain \
        --service-arn $SERVICE_ARN \
        --domain-name $DOMAIN_NAME \
        --enable-www-subdomain false \
        --region $AWS_REGION
    echo "✅ Custom domain associated"
fi
echo ""

echo "🎉 Deployment Complete!"
echo "======================="
echo ""
echo "📋 Deployment Summary:"
echo "   • App Runner URL: https://$APP_RUNNER_URL"
echo "   • Custom Domain: https://$DOMAIN_NAME"
echo "   • Database: $DB_ENDPOINT"
echo "   • SSL Certificate: $CERT_ARN"
echo ""
echo "🔧 Next Steps:"
echo "   1. Validate SSL certificate in AWS Console (if new)"
echo "   2. Wait 5-10 minutes for DNS propagation"
echo "   3. Test: https://$DOMAIN_NAME"
echo "   4. Configure API keys via environment variables"
echo ""
echo "💡 To update the application:"
echo "   ./deploy-autogen-aws.sh"
echo ""
echo "🔑 To add API keys:"
echo "   aws apprunner update-service --service-arn $SERVICE_ARN --source-configuration '{\"ImageRepository\":{\"ImageConfiguration\":{\"RuntimeEnvironmentVariables\":{\"OPENAI_API_KEY\":\"your-key\"}}}}'"
echo ""

# Save important info
cat > deployment-info.txt << EOF
AutoGen Studio Deployment Information
====================================
Date: $(date)
App Runner Service ARN: $SERVICE_ARN
App Runner URL: https://$APP_RUNNER_URL
Custom Domain: https://$DOMAIN_NAME
Database Endpoint: $DB_ENDPOINT
SSL Certificate ARN: $CERT_ARN
Hosted Zone ID: $HOSTED_ZONE_ID

To update environment variables:
aws apprunner update-service --service-arn $SERVICE_ARN --region $AWS_REGION --source-configuration file://source-config.json

To redeploy:
./deploy-autogen-aws.sh
EOF

echo "📄 Deployment info saved to: deployment-info.txt"
