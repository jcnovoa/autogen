#!/bin/bash

# AutoGen Studio AWS Deployment Script
# Account: 992257105959
# Region: us-east-1
# Domain: autogen.successkpis.world

set -e

# Configuration
AWS_ACCOUNT_ID="992257105959"
AWS_REGION="us-east-1"
ECR_REPOSITORY="autogen-studio"
APP_NAME="autogen-studio"
DOMAIN_NAME="autogen.successkpis.world"
DB_INSTANCE_ID="autogen-studio-db"

echo "🚀 Starting AutoGen Studio AWS Deployment"
echo "Account: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "Domain: $DOMAIN_NAME"
echo ""

# Check AWS CLI configuration
echo "📋 Checking AWS CLI configuration..."
aws sts get-caller-identity --region $AWS_REGION
echo ""

# Step 1: Create ECR Repository
echo "📦 Creating ECR Repository..."
aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION 2>/dev/null || \
aws ecr create-repository \
    --repository-name $ECR_REPOSITORY \
    --region $AWS_REGION \
    --image-scanning-configuration scanOnPush=true
echo "✅ ECR Repository ready"
echo ""

# Step 2: Build and Push Docker Image
echo "🔨 Building Docker image..."
docker build -t $ECR_REPOSITORY .

echo "🏷️ Tagging image for ECR..."
docker tag $ECR_REPOSITORY:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:latest

echo "🔐 Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

echo "📤 Pushing image to ECR..."
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:latest
echo "✅ Docker image pushed to ECR"
echo ""

# Step 3: Create RDS Database (if not exists)
echo "🗄️ Setting up RDS PostgreSQL database..."
DB_EXISTS=$(aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_ID --region $AWS_REGION 2>/dev/null || echo "false")

if [[ "$DB_EXISTS" == "false" ]]; then
    echo "Creating new RDS instance..."
    
    # Generate secure password
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
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
    
    echo "⏳ Waiting for RDS instance to be available..."
    aws rds wait db-instance-available --db-instance-identifier $DB_INSTANCE_ID --region $AWS_REGION
    
    # Get RDS endpoint
    DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier $DB_INSTANCE_ID \
        --region $AWS_REGION \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    # Store database credentials in Secrets Manager
    echo "🔐 Storing database credentials in Secrets Manager..."
    aws secretsmanager create-secret \
        --name "$APP_NAME/database" \
        --description "Database credentials for AutoGen Studio" \
        --secret-string "{\"username\":\"autogen_admin\",\"password\":\"$DB_PASSWORD\",\"host\":\"$DB_ENDPOINT\",\"port\":\"5432\",\"dbname\":\"postgres\"}" \
        --region $AWS_REGION
    
    DATABASE_URI="postgresql://autogen_admin:$DB_PASSWORD@$DB_ENDPOINT:5432/postgres"
else
    echo "RDS instance already exists"
    
    # Get existing database URI from Secrets Manager
    DB_SECRET=$(aws secretsmanager get-secret-value \
        --secret-id "$APP_NAME/database" \
        --region $AWS_REGION \
        --query 'SecretString' \
        --output text)
    
    DB_HOST=$(echo $DB_SECRET | jq -r '.host')
    DB_USER=$(echo $DB_SECRET | jq -r '.username')
    DB_PASS=$(echo $DB_SECRET | jq -r '.password')
    DATABASE_URI="postgresql://$DB_USER:$DB_PASS@$DB_HOST:5432/postgres"
fi

echo "✅ Database ready"
echo ""

# Step 4: Create App Runner Service
echo "🏃 Creating App Runner service..."

# Check if service already exists
SERVICE_EXISTS=$(aws apprunner list-services --region $AWS_REGION --query "ServiceSummaryList[?ServiceName=='$APP_NAME']" --output text)

if [[ -z "$SERVICE_EXISTS" ]]; then
    echo "Creating new App Runner service..."
    
    # Create apprunner.yaml configuration
    cat > apprunner.yaml << EOF
version: 1.0
runtime: docker
build:
  commands:
    build:
      - echo "Build completed"
run:
  runtime-version: latest
  command: uv run autogenstudio ui --host 0.0.0.0 --port 8080 --database-uri "\$DATABASE_URI"
  network:
    port: 8080
    env:
      - DATABASE_URI
      - OPENAI_API_KEY
      - ANTHROPIC_API_KEY
      - AZURE_OPENAI_API_KEY
EOF

    # Create the service
    aws apprunner create-service \
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
        --region $AWS_REGION
    
    echo "⏳ Waiting for App Runner service to be ready..."
    aws apprunner wait service-running --service-arn $(aws apprunner list-services --region $AWS_REGION --query "ServiceSummaryList[?ServiceName=='$APP_NAME'].ServiceArn" --output text) --region $AWS_REGION
else
    echo "App Runner service already exists, updating..."
    SERVICE_ARN=$(aws apprunner list-services --region $AWS_REGION --query "ServiceSummaryList[?ServiceName=='$APP_NAME'].ServiceArn" --output text)
    
    aws apprunner start-deployment \
        --service-arn $SERVICE_ARN \
        --region $AWS_REGION
fi

# Get App Runner URL
APP_RUNNER_URL=$(aws apprunner describe-service \
    --service-arn $(aws apprunner list-services --region $AWS_REGION --query "ServiceSummaryList[?ServiceName=='$APP_NAME'].ServiceArn" --output text) \
    --region $AWS_REGION \
    --query 'Service.ServiceUrl' \
    --output text)

echo "✅ App Runner service ready at: $APP_RUNNER_URL"
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
    echo "⚠️  Please validate the certificate via DNS in the AWS Console"
else
    echo "SSL certificate already exists: $CERT_ARN"
fi
echo ""

# Step 6: Get Route 53 Hosted Zone
echo "🌐 Setting up DNS..."
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
    --query "HostedZones[?Name=='successkpis.world.'].Id" \
    --output text | cut -d'/' -f3)

if [[ -n "$HOSTED_ZONE_ID" ]]; then
    echo "Found hosted zone: $HOSTED_ZONE_ID"
    
    # Create/Update CNAME record
    cat > change-batch.json << EOF
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

    aws route53 change-resource-record-sets \
        --hosted-zone-id $HOSTED_ZONE_ID \
        --change-batch file://change-batch.json
    
    rm change-batch.json
    echo "✅ DNS record created/updated"
else
    echo "⚠️  Hosted zone for successkpis.world not found"
    echo "Please create the hosted zone or update the domain configuration"
fi

echo ""
echo "🎉 Deployment completed!"
echo ""
echo "📋 Deployment Summary:"
echo "   • App Runner URL: https://$APP_RUNNER_URL"
echo "   • Custom Domain: https://$DOMAIN_NAME (after DNS propagation)"
echo "   • Database: $DB_INSTANCE_ID"
echo "   • ECR Repository: $ECR_REPOSITORY"
echo ""
echo "🔧 Next Steps:"
echo "   1. Validate SSL certificate in AWS Console"
echo "   2. Wait for DNS propagation (5-10 minutes)"
echo "   3. Test the application at https://$DOMAIN_NAME"
echo "   4. Configure API keys in environment variables"
echo ""
echo "💡 To update the application:"
echo "   ./deploy-to-aws.sh"
echo ""

# Cleanup
rm -f apprunner.yaml
