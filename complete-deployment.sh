#!/bin/bash

# Complete AutoGen Studio AWS Deployment
# Run this after Docker image has been pushed to ECR
# Account: 992257105959, Region: us-east-1

set -e

# Configuration
AWS_ACCOUNT_ID="992257105959"
AWS_REGION="us-east-1"
ECR_REPOSITORY="autogen-studio"
APP_NAME="autogen-studio"
DOMAIN_NAME="autogen.successkpis.world"
HOSTED_ZONE_ID="Z01161512I4PAKIUL4YRN"
DB_INSTANCE_ID="autogen-studio-db"
DB_PASSWORD="AutoGenStudio2024!SecurePass"

echo "🚀 Completing AutoGen Studio AWS Deployment"
echo "============================================="
echo "Account: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "Domain: $DOMAIN_NAME"
echo ""

# Verify AWS credentials
echo "🔐 Verifying AWS credentials..."
aws sts get-caller-identity --region $AWS_REGION > /dev/null
echo "✅ AWS credentials verified"
echo ""

# Step 1: Create RDS Database
echo "🗄️ Creating RDS PostgreSQL database..."
if aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_ID --region $AWS_REGION &>/dev/null; then
    echo "✅ RDS instance already exists"
    
    # Get existing database endpoint
    DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier $DB_INSTANCE_ID \
        --region $AWS_REGION \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
else
    echo "Creating new RDS instance..."
    
    aws rds create-db-instance \
        --db-instance-identifier $DB_INSTANCE_ID \
        --db-instance-class db.t3.micro \
        --engine postgres \
        --engine-version 15.13 \
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
    
    echo "✅ RDS instance created"
fi

DATABASE_URI="postgresql://autogen_admin:$DB_PASSWORD@$DB_ENDPOINT:5432/postgres"
echo "✅ Database ready at: $DB_ENDPOINT"
echo ""

# Step 2: Store database credentials in Secrets Manager
echo "🔐 Storing database credentials in Secrets Manager..."
if aws secretsmanager describe-secret --secret-id "$APP_NAME/database" --region $AWS_REGION &>/dev/null; then
    echo "✅ Database secret already exists"
else
    aws secretsmanager create-secret \
        --name "$APP_NAME/database" \
        --description "Database credentials for AutoGen Studio" \
        --secret-string "{\"username\":\"autogen_admin\",\"password\":\"$DB_PASSWORD\",\"host\":\"$DB_ENDPOINT\",\"port\":\"5432\",\"dbname\":\"postgres\"}" \
        --region $AWS_REGION
    echo "✅ Database credentials stored"
fi
echo ""

# Step 3: Create App Runner Service
echo "🏃 Creating App Runner service..."
SERVICE_ARN=$(aws apprunner list-services --region $AWS_REGION --query "ServiceSummaryList[?ServiceName=='$APP_NAME'].ServiceArn" --output text)

if [[ -z "$SERVICE_ARN" ]]; then
    echo "Creating new App Runner service..."
    
    # Create the service with proper authentication configuration
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
                \"ImageRepositoryType\": \"ECR\",
                \"AutoDeploymentsEnabled\": false
            },
            \"AutoDeploymentsEnabled\": false
        }" \
        --instance-configuration "{
            \"Cpu\": \"1 vCPU\",
            \"Memory\": \"2 GB\"
        }" \
        --auto-scaling-configuration-arn "arn:aws:apprunner:$AWS_REGION:$AWS_ACCOUNT_ID:autoscalingconfiguration/DefaultConfiguration/1/00000000000000000000000000000001" \
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

# Step 4: Request SSL Certificate
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

# Step 5: Create DNS Record
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

# Step 6: Associate Custom Domain with App Runner
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
echo "🔑 To add API keys:"
echo "   aws apprunner update-service --service-arn $SERVICE_ARN --region $AWS_REGION \\"
echo "     --source-configuration '{\"ImageRepository\":{\"ImageConfiguration\":{\"RuntimeEnvironmentVariables\":{\"OPENAI_API_KEY\":\"your-key\"}}}}'"
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
Database URI: $DATABASE_URI
SSL Certificate ARN: $CERT_ARN
Hosted Zone ID: $HOSTED_ZONE_ID

To update environment variables:
aws apprunner update-service --service-arn $SERVICE_ARN --region $AWS_REGION --source-configuration file://source-config.json

To redeploy:
./complete-deployment.sh
EOF

echo "📄 Deployment info saved to: deployment-info.txt"
