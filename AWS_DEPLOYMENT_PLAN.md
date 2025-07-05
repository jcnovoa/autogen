# AutoGen Studio AWS Deployment Plan

## Architecture Overview

### Option 1: AWS App Runner (Recommended)
```
Internet → Route 53 → App Runner → RDS PostgreSQL
                   ↓
                CloudWatch Logs
```

### Option 2: ECS Fargate (Enterprise)
```
Internet → Route 53 → CloudFront → ALB → ECS Fargate → RDS PostgreSQL
                                                    ↓
                                                   EFS
```

## Deployment Strategy: AWS App Runner

### 1. Infrastructure Components

#### Core Services
- **AWS App Runner**: Host the AutoGen Studio application
- **Amazon RDS PostgreSQL**: Production database
- **Amazon Route 53**: DNS management for autogen.successkpis.world
- **AWS Certificate Manager**: SSL/TLS certificates
- **Amazon CloudWatch**: Logging and monitoring

#### Supporting Services
- **Amazon ECR**: Container registry
- **AWS Secrets Manager**: Store database credentials and API keys
- **Amazon S3**: Store application data and backups
- **AWS IAM**: Access control and permissions

### 2. Container Configuration

#### Dockerfile for AutoGen Studio
```dockerfile
FROM node:18-alpine AS frontend-builder
WORKDIR /app/frontend
COPY python/packages/autogen-studio/frontend/package.json .
COPY python/packages/autogen-studio/frontend/yarn.lock .
RUN yarn install
COPY python/packages/autogen-studio/frontend/ .
RUN yarn build

FROM python:3.11-slim
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    git-lfs \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY python/pyproject.toml python/uv.lock ./
RUN pip install uv && uv sync --no-dev

# Copy application code
COPY python/ ./
COPY --from=frontend-builder /app/frontend/public ./packages/autogen-studio/autogenstudio/web/ui/

# Set environment variables
ENV PYTHONPATH=/app
ENV PORT=8080

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Start command
CMD ["uv", "run", "autogenstudio", "ui", "--host", "0.0.0.0", "--port", "8080"]
```

### 3. Database Configuration

#### RDS PostgreSQL Setup
```yaml
Engine: PostgreSQL 15
Instance Class: db.t3.micro (start small, can scale)
Storage: 20GB GP3 (auto-scaling enabled)
Multi-AZ: No (for cost optimization, enable for production)
Backup Retention: 7 days
Encryption: Enabled
VPC: Default VPC in us-east-1
Security Group: Allow port 5432 from App Runner
```

#### Connection String Format
```
postgresql://username:password@autogen-db.cluster-xyz.us-east-1.rds.amazonaws.com:5432/autogen_studio
```

### 4. App Runner Configuration

#### Service Settings
```yaml
Service Name: autogen-studio
Source: Container Registry (ECR)
Port: 8080
CPU: 1 vCPU
Memory: 2 GB
Auto Scaling:
  Min: 1 instance
  Max: 10 instances
  Concurrency: 100 requests per instance
```

#### Environment Variables
```bash
DATABASE_URI=postgresql://user:pass@rds-endpoint:5432/autogen_studio
OPENAI_API_KEY=stored-in-secrets-manager
ANTHROPIC_API_KEY=stored-in-secrets-manager
AZURE_OPENAI_API_KEY=stored-in-secrets-manager
PYTHONPATH=/app
PORT=8080
```

### 5. Route 53 Configuration

#### DNS Records
```yaml
Domain: autogen.successkpis.world
Type: CNAME
Value: app-runner-service-url.us-east-1.awsapprunner.com
TTL: 300 seconds
```

#### SSL Certificate
- Use AWS Certificate Manager
- Request certificate for autogen.successkpis.world
- Validate via DNS (Route 53)

## Implementation Steps

### Phase 1: Infrastructure Setup

1. **Create RDS PostgreSQL Database**
```bash
aws rds create-db-instance \
    --db-instance-identifier autogen-studio-db \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --engine-version 15.4 \
    --master-username autogen_admin \
    --master-user-password [SECURE_PASSWORD] \
    --allocated-storage 20 \
    --storage-type gp3 \
    --storage-encrypted \
    --backup-retention-period 7 \
    --region us-east-1
```

2. **Create ECR Repository**
```bash
aws ecr create-repository \
    --repository-name autogen-studio \
    --region us-east-1
```

3. **Store Secrets in AWS Secrets Manager**
```bash
aws secretsmanager create-secret \
    --name autogen-studio/database \
    --description "Database credentials for AutoGen Studio" \
    --secret-string '{"username":"autogen_admin","password":"[SECURE_PASSWORD]","host":"[RDS_ENDPOINT]","port":"5432","dbname":"autogen_studio"}' \
    --region us-east-1
```

### Phase 2: Application Deployment

1. **Build and Push Container**
```bash
# Build the container
docker build -t autogen-studio .

# Tag for ECR
docker tag autogen-studio:latest 992257105959.dkr.ecr.us-east-1.amazonaws.com/autogen-studio:latest

# Push to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 992257105959.dkr.ecr.us-east-1.amazonaws.com
docker push 992257105959.dkr.ecr.us-east-1.amazonaws.com/autogen-studio:latest
```

2. **Create App Runner Service**
```bash
aws apprunner create-service \
    --service-name autogen-studio \
    --source-configuration '{
        "ImageRepository": {
            "ImageIdentifier": "992257105959.dkr.ecr.us-east-1.amazonaws.com/autogen-studio:latest",
            "ImageConfiguration": {
                "Port": "8080",
                "RuntimeEnvironmentVariables": {
                    "DATABASE_URI": "postgresql://autogen_admin:[PASSWORD]@[RDS_ENDPOINT]:5432/autogen_studio"
                }
            },
            "ImageRepositoryType": "ECR"
        }
    }' \
    --instance-configuration '{
        "Cpu": "1 vCPU",
        "Memory": "2 GB"
    }' \
    --auto-scaling-configuration-arn "arn:aws:apprunner:us-east-1:992257105959:autoscalingconfiguration/DefaultConfiguration/1/00000000000000000000000000000001" \
    --region us-east-1
```

### Phase 3: DNS and SSL Setup

1. **Request SSL Certificate**
```bash
aws acm request-certificate \
    --domain-name autogen.successkpis.world \
    --validation-method DNS \
    --region us-east-1
```

2. **Create Route 53 Record**
```bash
aws route53 change-resource-record-sets \
    --hosted-zone-id [HOSTED_ZONE_ID] \
    --change-batch '{
        "Changes": [{
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "autogen.successkpis.world",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [{"Value": "[APP_RUNNER_URL]"}]
            }
        }]
    }'
```

## Cost Estimation (Monthly)

### App Runner Option
- **App Runner**: ~$25-50/month (1 instance, moderate usage)
- **RDS PostgreSQL**: ~$15-25/month (db.t3.micro)
- **Route 53**: ~$0.50/month (hosted zone)
- **Certificate Manager**: Free
- **CloudWatch**: ~$5-10/month
- **Total**: ~$45-85/month

### Data Transfer
- First 1GB free
- Additional data transfer: $0.09/GB

## Security Considerations

### Network Security
- App Runner runs in AWS-managed VPC
- RDS in private subnets
- Security groups restrict database access
- WAF can be added for additional protection

### Application Security
- Secrets stored in AWS Secrets Manager
- Environment variables for non-sensitive config
- IAM roles for service-to-service communication
- CloudTrail for audit logging

### API Key Management
- Store all AI provider API keys in Secrets Manager
- Rotate keys regularly
- Use IAM roles for AWS service access
- Enable CloudWatch monitoring for unusual activity

## Monitoring and Logging

### CloudWatch Integration
- Application logs from App Runner
- Database performance metrics from RDS
- Custom metrics for user activity
- Alarms for error rates and response times

### Recommended Alarms
- High error rate (>5%)
- High response time (>5 seconds)
- Database connection failures
- Memory/CPU utilization >80%

## Backup and Disaster Recovery

### Database Backups
- Automated daily backups (7-day retention)
- Point-in-time recovery enabled
- Cross-region backup replication (optional)

### Application Data
- S3 backup for user-generated content
- Version control for application code
- Infrastructure as Code (CloudFormation/CDK)

## Scaling Strategy

### Automatic Scaling
- App Runner auto-scales based on traffic
- RDS can be upgraded to larger instances
- Read replicas for database scaling

### Performance Optimization
- CloudFront CDN for static assets
- ElastiCache for session storage
- Database query optimization

## Next Steps

1. **Immediate**: Set up RDS PostgreSQL database
2. **Week 1**: Build and deploy container to ECR
3. **Week 1**: Create App Runner service
4. **Week 1**: Configure Route 53 and SSL
5. **Week 2**: Set up monitoring and alerts
6. **Week 2**: Performance testing and optimization
7. **Week 3**: Security review and hardening
8. **Week 4**: Documentation and runbooks

This architecture provides a production-ready, scalable, and cost-effective deployment of AutoGen Studio on AWS with professional DNS setup.
