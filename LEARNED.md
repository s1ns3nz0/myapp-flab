# What happend for this project and How could I fix them?
## 1) Error 1: ACM Certificate Validation Stuck
### What happened
```
aws_acm_certificate_validation.main → Still creating... (15+ minutes)
```
### Root Cause
- I already manually create the hosted zones in AWS through dashboard
- New hosted zone was planned to be deployed by terraform code
- ACM certificate validation was performed through the new hosted zone created by terraform code
- It couldn't validate the dns so that it took so many attempts finally it failed
### How I found
- Manually checked the real nameservers of my dns 
`dig <DNS>`
### How I fixed
```
# Before: Creating new hosted zone every time
resource "aws_route53_zone" "main"{
    name = var.domain_name
}

# After: Reference existing hosted zone
data "aws_route53_zone" "main"{
    name = var.domain_name
    private = false # Public DNS, Private = Available only in VPC
}
```
## 2) Error 2: Duplicate ACM Validation Record
### What happened
- ACM Validation Record(CNAME) already exists
```
Error: creating Route53 Record
InvalidChangeBatch: Tried to create resource record set
[name='_24e76f5fa8e60f0a98deea60d00f5b67.miata.cloud.', type='CNAME']
but it already exists
```
### Root Cause
- ACM DNS validation record is already created by terraform apply command in a previous attempt
- Terraform tried to create the record again, which caused a conflict.
### How I found
- Manually verify the AWS Console with the terraform error message shown in the terminal.
### How I fixed
```
# Before: Not overwrite the record (CNAME)
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true  # ← Added this: overwrite if already exists
}
```
## 3) Error 3: ALB Access Logs Permission Denied
### What happend
- The bucket IAM policy did not allow the ALB service account to put the objects into an S3 bucket.
```
Error: modifying ELBv2 Load Balancer attributes
InvalidConfigurationRequest: Access Denied for bucket: myapp-flab-prd
Please check S3 bucket permission
```
### Root Cause
- ALB which tried to write access logs into the S3 bucket did not have sufficient permissions to access the S3 bucket.
### How I fixed
#### 1.1 Disable ALB access logs
````
resource "aws_lb" "main"{
    access_logs {
        bucket = "myapp-flab-prd"
        prefix = "alb-logs"
        enable = false # <- Disable logging
    }
}
````
#### 1.2 Make A New IAM Policy for ALB 
- Made a new AWS IAM policy for ALB to put objects into the bucket.
- To leverage this method, refer to the service account of ALB.
````
data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "alb_logs" {
  policy = jsonencode({
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.main.arn }
      Action    = "s3:PutObject"
      Resource  = "arn:aws:s3:::myapp-flab-prd/alb-logs/*"
    }]
  })
}
````
## 4) Error 4: WAF Description Rejected Korean Characters
### What happend
```
Error: creating WAFv2 IPSet (myapp-flab-prd-blocklist)
ValidationException: Value '차단할 IP 목록' at 'description'
failed to satisfy constraint:
Member must satisfy regular expression pattern: ^[\w+=:#@/\-,\.][\w+=:#@/\-,\.\s]+[\w+=:#@/\-,\.]$
```
### Root Cause
- Korean characters existed in WAF rule descriptions.
### How I found
- I looked into the WAF Terraform code description including Korean characters.
### How I fixed
- Replace Korean characters to English.
```
# Before
resource "aws_wafv2_ip_set" "blocklist" {
  description = "차단할 IP 목록"  # Korean → rejected
}

# After
resource "aws_wafv2_ip_set" "blocklist" {
  description = "IP blocklist for ${var.project_name}"  # English only
}
```
## 5) Error 5: ECS Tasks Failing to Start (ExitCode: 1)
### What happend
- ECS Container abnormally exited with ExitCode 1
```
StoppedReason: Essential container in task exited
ExitCode: 1
```
### How I found
- Look into the CloudWatch logs.
```
botocore.exceptions.ClientError:
An error occurred (ValidationException) when calling
the GetSecretValue operation:
Invalid name. Must be a valid name containing
alphanumeric characters, or any of the following: -/_+=.@!
```
### Root Cause
- The application code related to DB login could not properly handle the return value from AWS SecretManager.
- The format of returned value was JSON
### How I fixed
- Modified the database.py code to properly handle the returned value from SecretsManager.
```
# ❌ Before: Assumed secret_arn was always an ARN
def get_secret():
    secret_arn = os.getenv("DB_SECRET")
    client = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=secret_arn)
    # → Failed when secret value string was passed instead of ARN

# ✅ After: Handle all possible injection formats
def get_secret():
    db_secret = os.getenv("DB_SECRET")

    # Case 1: JSON string injected directly by ECS
    try:
        secret_data = json.loads(db_secret)
        return {
            "username": secret_data.get("username", "admin"),
            "password": secret_data.get("password", "")
        }
    except json.JSONDecodeError:
        pass

    # Case 2: ARN string → call Secrets Manager directly
    if db_secret.startswith("arn:aws:secretsmanager"):
        client = boto3.client("secretsmanager", region_name="ap-northeast-2")
        response = client.get_secret_value(SecretId=db_secret)
        secret_data = json.loads(response["SecretString"])
        return {
            "username": secret_data.get("username", "admin"),
            "password": secret_data.get("password", "")
        }

    # Case 3: Plain password string
    return {
        "username": os.getenv("DB_USER", "admin"),
        "password": db_secret
    }
```
## 6) Error 6: ECS Target.Timeout (The Main One!)
### What happend
- ALB health check failed. 
```
ALB Health Check results:
Target: i-0604dfd3b920fe801 → Health: unhealthy → Reason: Target.Timeout
Target: i-0de81487cb783c86c → Health: unhealthy → Reason: Target.Timeout
```
### Root Cause
- When using EC2 instances to host containers in ECS, automatically random ports of within the ranges 32768~65535 are assigned to containers on instances.
- ECS security group only allowed traffic through port 8080.
- ALB health check traffic was denied by ECS security group.

### How I fixed
```
# Before: Only allow traffic of port 8080
resource "aws_security_group_rule" "ecs_inbound"{
    from_port = 8080
    to_port   = 8080
    protocol  = tcp
    source_security_group_id = aws_security_group.alb.id
}

# After: Allow traffic from 32768 to 65535
resource "aws_security_group_rule" "ecs_inbound"{
    from_port = 32768
    to_port   = 65535
    protocol  = tcp
    source_security_group_id = aws_security_group.alb.id
}
```