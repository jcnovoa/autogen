# AutoGen Studio AWS Deployment Guide

## Overview

This guide provides complete instructions for deploying AutoGen Studio to AWS with a custom domain `autogen.successkpis.world`.

## Architecture

```
Internet → Route 53 → App Runner → RDS PostgreSQL
                   ↓
               CloudWatch Logs
```

### AWS Services Used
- **AWS App Runner**: Containerized application hosting
- **Amazon RDS PostgreSQL**: Production database
- **Amazon Route 53**: DNS management
- **AWS Certificate Manager**: SSL/TLS certificates
- **Amazon ECR**: Container registry
- **AWS Secrets Manager**: Secure credential storage

## Prerequisites

### 1. AWS Account Setup
- AWS Account: `992257105959`
- Region: `us-east-1`
- Domain: `autogen.successkpis.world` (already registered)
- Hosted Zone ID: `Z01161512I4PAKIUL4YRN`

### 2. Local Requirements
- Docker installed and running
- AWS CLI configured with appropriate permissions
- Git with Git LFS support
- Node.js 18+ and Yarn (for frontend build)

### 3. Required AWS Permissions
Your AWS user/role needs permissions for:
- ECR (create repositories, push images)
- App Runner (create/manage services)
- RDS (create/manage databases)
- Route 53 (manage DNS records)
- Certificate Manager (request/manage certificates)
- Secrets Manager (store/retrieve secrets)

## Quick Deployment

### Option 1: Automated Script (Recommended)

```bash
# Clone the repository (if not already done)
cd /Users/j.c.novoa/Development/GenAI/autogen

# Run the deployment script
./deploy-autogen-aws.sh
```

This script will:
1. Create ECR repository
2. Build and push Docker image
3. Create RDS PostgreSQL database
4. Deploy App Runner service
5. Request SSL certificate
6. Configure DNS records
7. Associate custom domain

### Option 2: Manual Step-by-Step

#### Step 1: Build Frontend
```bash
cd python/packages/autogen-studio/frontend
yarn install
yarn build
```

#### Step 2: Create ECR Repository
```bash
aws ecr create-repository \
    --repository-name autogen-studio \
    --region us-east-1
```

#### Step 3: Build and Push Docker Image
```bash
# Build image
docker build -t autogen-studio .

# Tag for ECR
docker tag autogen-studio:latest 992257105959.dkr.ecr.us-east-1.amazonaws.com/autogen-studio:latest

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 992257105959.dkr.ecr.us-east-1.amazonaws.com

# Push image
docker push 992257105959.dkr.ecr.us-east-1.amazonaws.com/autogen-studio:latest
```

#### Step 4: Create RDS Database
```bash
aws rds create-db-instance \
    --db-instance-identifier autogen-studio-db \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --engine-version 15.4 \
    --master-username autogen_admin \
    --master-user-password YOUR_SECURE_PASSWORD \
    --allocated-storage 20 \
    --storage-type gp3 \
    --storage-encrypted \
    --backup-retention-period 7 \
    --publicly-accessible \
    --region us-east-1
```

#### Step 5: Create App Runner Service
```bash
aws apprunner create-service \
    --service-name autogen-studio \
    --source-configuration file://apprunner-config.json \
    --instance-configuration '{"Cpu": "1 vCPU", "Memory": "2 GB"}' \
    --region us-east-1
```

## Configuration

### Environment Variables

The application requires these environment variables:

```bash
# Database (automatically configured)
DATABASE_URI=postgresql://username:password@host:5432/database

# AI Provider API Keys (configure after deployment)
OPENAI_API_KEY=your_openai_api_key
ANTHROPIC_API_KEY=your_anthropic_api_key
AZURE_OPENAI_API_KEY=your_azure_openai_api_key
```

### Adding API Keys After Deployment

1. **Via AWS Console:**
   - Go to App Runner → Services → autogen-studio
   - Configuration → Environment variables
   - Add your API keys

2. **Via AWS CLI:**
```bash
aws apprunner update-service \
    --service-arn YOUR_SERVICE_ARN \
    --source-configuration '{
        "ImageRepository": {
            "ImageConfiguration": {
                "RuntimeEnvironmentVariables": {
                    "OPENAI_API_KEY": "your-key-here",
                    "ANTHROPIC_API_KEY": "your-key-here"
                }
            }
        }
    }' \
    --region us-east-1
```

## Post-Deployment Steps

### 1. SSL Certificate Validation
- Go to AWS Certificate Manager console
- Find the certificate for `autogen.successkpis.world`
- Complete DNS validation if required

### 2. DNS Propagation
- Wait 5-10 minutes for DNS changes to propagate
- Test with: `nslookup autogen.successkpis.world`

### 3. Application Testing
- Access: https://autogen.successkpis.world
- Verify the AutoGen Studio interface loads
- Test basic functionality

### 4. Configure API Keys
- Add your AI provider API keys via AWS Console or CLI
- Restart the App Runner service to apply changes

## Monitoring and Maintenance

### CloudWatch Logs
- Application logs: `/aws/apprunner/autogen-studio`
- Database logs: Available in RDS console

### Health Checks
- App Runner health check: `/docs` endpoint
- Manual health check: `curl https://autogen.successkpis.world/docs`

### Scaling
- App Runner auto-scales based on traffic
- Default: 1-10 instances, 100 concurrent requests per instance
- Database can be scaled vertically as needed

## Cost Optimization

### Current Configuration Costs (Monthly)
- **App Runner**: ~$25-50 (1-2 instances)
- **RDS PostgreSQL**: ~$15-25 (db.t3.micro)
- **Route 53**: ~$0.50 (hosted zone)
- **Certificate Manager**: Free
- **Data Transfer**: ~$5-10
- **Total**: ~$45-85/month

### Cost Reduction Options
1. Use RDS Aurora Serverless v2 for variable workloads
2. Enable App Runner auto-pause for development
3. Use CloudFront CDN to reduce data transfer costs

## Troubleshooting

### Common Issues

#### 1. Frontend Not Loading
```bash
# Rebuild frontend
cd python/packages/autogen-studio/frontend
yarn build

# Rebuild and redeploy container
docker build -t autogen-studio .
./deploy-autogen-aws.sh
```

#### 2. Database Connection Issues
- Check RDS security groups
- Verify database credentials in Secrets Manager
- Test connection from App Runner logs

#### 3. SSL Certificate Issues
- Ensure DNS validation is complete
- Check certificate status in ACM console
- Verify domain ownership

#### 4. DNS Resolution Issues
- Check Route 53 record configuration
- Verify hosted zone is correct
- Wait for DNS propagation (up to 48 hours)

### Logs and Debugging

#### View App Runner Logs
```bash
aws logs describe-log-streams \
    --log-group-name /aws/apprunner/autogen-studio \
    --region us-east-1

aws logs get-log-events \
    --log-group-name /aws/apprunner/autogen-studio \
    --log-stream-name LOG_STREAM_NAME \
    --region us-east-1
```

#### Database Monitoring
- RDS Performance Insights (enabled by default)
- CloudWatch metrics for database performance
- Query logs can be enabled if needed

## Security Considerations

### Network Security
- App Runner runs in AWS-managed VPC
- RDS accessible only from App Runner
- HTTPS enforced with SSL certificate

### Secrets Management
- Database credentials in AWS Secrets Manager
- API keys stored as environment variables
- No hardcoded secrets in container images

### Access Control
- IAM roles for service-to-service communication
- Principle of least privilege
- CloudTrail logging enabled

## Backup and Recovery

### Database Backups
- Automated daily backups (7-day retention)
- Point-in-time recovery available
- Manual snapshots can be created

### Application Recovery
- Container images stored in ECR
- Infrastructure as Code (deployment scripts)
- Configuration stored in AWS services

## Updates and Maintenance

### Application Updates
```bash
# Update code and redeploy
git pull origin main
./deploy-autogen-aws.sh
```

### Database Maintenance
- Automatic minor version updates enabled
- Major version updates require manual intervention
- Maintenance window: Sunday 3-4 AM UTC

### Security Updates
- Container base images updated regularly
- AWS services automatically patched
- Monitor AWS Security Bulletins

## Support and Documentation

### AWS Resources
- [App Runner Documentation](https://docs.aws.amazon.com/apprunner/)
- [RDS PostgreSQL Guide](https://docs.aws.amazon.com/rds/latest/userguide/)
- [Route 53 Documentation](https://docs.aws.amazon.com/route53/)

### AutoGen Resources
- [AutoGen Documentation](https://microsoft.github.io/autogen/)
- [AutoGen Studio Guide](https://microsoft.github.io/autogen/docs/autogen-studio/)
- [GitHub Repository](https://github.com/microsoft/autogen)

### Emergency Contacts
- AWS Support (if enabled)
- Internal DevOps team
- Application maintainers

---

## Quick Reference

### Important URLs
- **Application**: https://autogen.successkpis.world
- **API Docs**: https://autogen.successkpis.world/docs
- **AWS Console**: https://console.aws.amazon.com/

### Key AWS Resources
- **Account ID**: 992257105959
- **Region**: us-east-1
- **Hosted Zone**: Z01161512I4PAKIUL4YRN
- **ECR Repository**: autogen-studio
- **App Runner Service**: autogen-studio
- **RDS Instance**: autogen-studio-db

### Useful Commands
```bash
# Redeploy application
./deploy-autogen-aws.sh

# View logs
aws logs tail /aws/apprunner/autogen-studio --follow --region us-east-1

# Check service status
aws apprunner describe-service --service-arn SERVICE_ARN --region us-east-1

# Update environment variables
aws apprunner update-service --service-arn SERVICE_ARN --source-configuration file://config.json --region us-east-1
```
