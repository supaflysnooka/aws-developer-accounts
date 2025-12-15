# Utilities Scripts

Helper scripts for maintenance, backup, documentation generation, and resource management.

## Overview

These utility scripts provide essential maintenance and operational tasks:
- Terraform state backup and recovery
- Unused resource cleanup for cost optimization
- Automated documentation generation
- Key rotation (placeholder for future implementation)

## Scripts

### `backup-state.sh`

**Purpose**: Creates comprehensive backups of all Terraform state files and related resources

**Features**:
- Backs up local Terraform state files
- Downloads remote state from S3
- Exports DynamoDB lock table data
- Backs up Terraform outputs
- Creates detailed backup manifest
- Optional compression and S3 upload
- Automated old backup cleanup

**Usage**:

```bash
./backup-state.sh
```

**Interactive Workflow**:
1. Prerequisites check
2. Create backup directory with timestamp
3. Backup local state files
4. Download remote state from S3 (including versions)
5. Export DynamoDB lock tables
6. Capture Terraform outputs
7. Generate backup manifest
8. Optional: Compress backup archive
9. Optional: Upload to S3
10. Optional: Clean up old backups

**Backup Structure**:
```
backups/terraform-state/YYYYMMDD_HHMMSS/
├── MANIFEST.md              # Backup documentation
├── local/                   # Local state files
│   └── environments/
│       └── dev-accounts/
│           ├── terraform.tfstate
│           └── terraform.tfstate.backup
├── remote/                  # Remote state from S3
│   └── bucket-name/
│       ├── terraform.tfstate
│       ├── terraform.tfstate.version1
│       └── terraform.tfstate.version2
├── dynamodb/                # Lock table exports
│   └── terraform-locks.json
└── outputs/                 # Terraform outputs
    └── environments/
        └── dev-accounts/
            └── outputs.json
```

**Manifest Contents**:
- Backup creation timestamp
- User who created backup
- Git branch and commit
- List of backed up files
- Backup size
- Restoration instructions
- Retention policy

**Compression & Upload**:
```bash
# After backup completes, optionally:
# 1. Create tar.gz archive
# 2. Upload to S3 backup bucket
# 3. Delete uncompressed backup

# Example S3 upload
aws s3 cp terraform-state-backup-20250106.tar.gz \
  s3://backup-bucket/terraform-backups/
```

**Retention Policy**:
- Daily backups: Keep 7 days
- Weekly backups: Keep 4 weeks
- Monthly backups: Keep 12 months
- Manual cleanup or automated via script

**Recovery Process**:
```bash
# 1. Stop all Terraform operations
# 2. Navigate to backup directory
cd backups/terraform-state/20250106_143022

# 3. Restore state file
cp local/environments/dev-accounts/terraform.tfstate \
   ../../environments/dev-accounts/terraform.tfstate

# 4. Verify state
cd ../../environments/dev-accounts
terraform state list

# 5. Test with plan
terraform plan
```

**Best Practices**:
- Backup before major changes
- Backup before `terraform apply`
- Test restoration process regularly
- Store backups in separate AWS account
- Encrypt backup archives
- Keep backups for compliance period

---

### `cleanup-resources.sh`

**Purpose**: Identifies and removes unused AWS resources to reduce costs

**Features**:
- Scans for unused Elastic IPs
- Finds unattached EBS volumes
- Identifies old EBS snapshots (>90 days)
- Detects unused AMIs
- Finds incomplete S3 multipart uploads
- Checks CloudWatch log retention policies
- Identifies unused load balancers
- Lists stopped EC2 instances
- Finds unused security groups
- Calculates potential cost savings

**Usage**:

```bash
# Dry run (default - no changes made)
./cleanup-resources.sh

# Execute mode (actually deletes resources)
./cleanup-resources.sh --execute
```

**Dry Run Mode** (Default):
- Identifies unused resources
- Calculates potential savings
- **Does not delete anything**
- Safe to run anytime

**Execute Mode**:
- Prompts for confirmation before each deletion
- Creates snapshots before deleting volumes
- Empties S3 buckets before deletion
- **Actually removes resources**

**Resources Checked**:

**1. Unused Elastic IPs**:
- Cost: ~$3.65/month per unattached EIP
- Detection: EIPs not associated with instances
- Action: Release unattached EIPs

**2. Unattached EBS Volumes**:
- Cost: $0.08/GB/month (gp3)
- Detection: Volumes in "available" state
- Action: Snapshot then delete

**3. Old EBS Snapshots**:
- Cost: $0.05/GB/month
- Detection: Snapshots older than 90 days
- Action: Delete old snapshots

**4. Unused AMIs**:
- Cost: Storage costs for associated snapshots
- Detection: AMIs not used by any instances
- Action: Deregister and delete snapshots

**5. Incomplete Multipart Uploads**:
- Cost: Storage without visibility
- Detection: S3 multipart uploads not completed
- Action: Abort incomplete uploads

**6. CloudWatch Logs Without Retention**:
- Cost: $0.50/GB/month storage
- Detection: Log groups without retention policy
- Action: Set 30-day retention

**7. Unused Load Balancers**:
- Cost: ~$16.20/month per ALB
- Detection: ALBs with no healthy targets
- Action: Manual review recommended

**8. Stopped EC2 Instances**:
- Cost: EBS storage still charged
- Detection: Instances in "stopped" state
- Action: Consider termination

**9. Unused Security Groups**:
- Cost: None (but clutter)
- Detection: SGs not attached to any ENIs
- Action: Delete unused SGs

**Cost Savings Report**:
```
Total Potential Savings: $147.50/month

Breakdown:
- Elastic IPs: $14.60/month (4 IPs)
- EBS Volumes: $80.00/month (1TB unattached)
- Snapshots: $25.00/month (500GB old snapshots)
- Load Balancers: $16.20/month (1 unused ALB)
- Logs: $11.70/month (23GB without retention)
```

**Safety Features**:
- Dry run by default
- Multiple confirmation prompts
- Creates backups before deletion
- Detailed logging of all actions
- Ability to cancel at any step

**Recommendations**:
1. Run weekly in dry run mode
2. Review findings with team
3. Execute cleanup during maintenance window
4. Monitor cost reports after cleanup
5. Automate with monthly schedule

---

### `generate-docs.sh`

**Purpose**: Automatically generates and updates documentation for Terraform modules

**Features**:
- Extracts variables from `variables.tf`
- Extracts outputs from `outputs.tf`
- Generates module README files
- Creates markdown tables for variables/outputs
- Updates main project README
- Generates CHANGELOG template
- Creates CONTRIBUTING guide
- Builds module index

**Usage**:

```bash
./generate-docs.sh
```

**Interactive Workflow**:
1. Confirmation to proceed
2. Generate README for each module
3. Update main project README
4. Create/update CHANGELOG
5. Create/update CONTRIBUTING guide
6. Generate module index

**Generated README Structure**:

```markdown
# Module Name

## Description
[Module purpose and use case]

## Usage
```hcl
module "example" {
  source = "../../modules/category/module-name"
  # Variables here
}
```

## Variables
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `name` | string | - | Resource name |
| `enabled` | bool | true | Enable feature |

## Outputs
| Output | Description |
|--------|-------------|
| `id` | Resource ID |
| `arn` | Resource ARN |

## Examples
### Basic Example
### Advanced Example

## Requirements
| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | ~> 5.0 |

## Resources
[List of AWS resources created]

## Notes
[Additional information]
```

**Variable Extraction**:
- Parses `variables.tf` files
- Extracts variable name, type, default, description
- Formats as markdown table
- Handles complex types (list, map, object)

**Output Extraction**:
- Parses `outputs.tf` files
- Extracts output name and description
- Formats as markdown table

**Generated Files**:
```
modules/
├── networking/
│   ├── vpc/
│   │   └── README.md           # Generated
│   ├── security-groups/
│   │   └── README.md           # Generated
│   └── alb/
│       └── README.md           # Generated
├── compute/
│   └── ec2/
│       └── README.md           # Generated
CHANGELOG.md                    # Generated
CONTRIBUTING.md                 # Generated
docs/
└── MODULE_INDEX.md            # Generated
```

**CHANGELOG Template**:
```markdown
# Changelog

All notable changes documented here.

## [Unreleased]

### Added
- New features

### Changed
- Modified functionality

### Fixed
- Bug fixes

## [1.0.0] - YYYY-MM-DD
### Added
- Initial release
```

**CONTRIBUTING Guide**:
- Development setup instructions
- Code standards (Terraform, documentation)
- Testing requirements
- Pull request process
- Code review guidelines
- Module development guide

**Module Index**:
- Complete list of all modules
- Module paths and purposes
- Quick reference guide
- Organized by category

**Customization**:

Edit the script to customize templates:
```bash
# Find template sections
cat > "$readme_file" <<EOF
# Your custom template here
EOF
```

**Best Practices**:
- Run after creating new modules
- Run after modifying variables/outputs
- Review generated docs before committing
- Manually add examples and use cases
- Keep descriptions concise and clear
- Update CHANGELOG with each release

**Manual Updates Required**:
After generation, manually add:
- Module descriptions
- Usage examples (basic and advanced)
- Resource lists
- Additional notes and warnings
- Cost considerations
- Security considerations

---

### `rotate-keys.sh`

**Purpose**: Reserved for future key rotation automation (currently empty)

**Planned Features**:
- Automated IAM access key rotation
- Database credential rotation
- API key management
- Secret rotation schedules
- Notification of rotation events

**Current Status**: Placeholder for future implementation

**Manual Key Rotation** (until script is implemented):

**IAM Access Keys**:
```bash
# 1. Create new access key
aws iam create-access-key --user-name username

# 2. Update applications with new key
# 3. Test applications

# 4. Delete old access key
aws iam delete-access-key \
  --user-name username \
  --access-key-id AKIAIOSFODNN7EXAMPLE
```

**RDS Credentials**:
```bash
# Use AWS Secrets Manager rotation
aws secretsmanager rotate-secret \
  --secret-id rds-database-secret \
  --rotation-lambda-arn arn:aws:lambda:...
```

**Secrets Manager Secrets**:
```bash
# Enable automatic rotation
aws secretsmanager rotate-secret \
  --secret-id my-secret \
  --rotation-rules AutomaticallyAfterDays=30
```

---

## Common Use Cases

### Regular Maintenance Routine

**Weekly Tasks**:
```bash
# 1. Backup Terraform state
./scripts/utilities/backup-state.sh

# 2. Scan for unused resources (dry run)
./scripts/utilities/cleanup-resources.sh

# 3. Review cost savings opportunities
# Check output from cleanup script
```

**Monthly Tasks**:
```bash
# 1. Clean up old backups
cd backups/terraform-state
ls -lt | tail -n +8 | awk '{print $9}' | xargs rm -rf

# 2. Execute resource cleanup
./scripts/utilities/cleanup-resources.sh --execute

# 3. Update documentation
./scripts/utilities/generate-docs.sh

# 4. Review and commit docs
git add modules/*/README.md CHANGELOG.md
git commit -m "docs: update module documentation"
```

### Pre-Deployment Checklist

```bash
# 1. Backup current state
./scripts/utilities/backup-state.sh

# 2. Validate configuration
./scripts/validation/validate-terraform.sh

# 3. Run security scan
./scripts/validation/security-scan.sh

# 4. Check compliance
./scripts/validation/compliance-check.sh

# 5. Estimate costs
./scripts/validation/cost-estimate.sh

# 6. Proceed with deployment if all checks pass
cd environments/dev-accounts
terraform apply
```

### Disaster Recovery

**Scenario: Corrupted Terraform state**

```bash
# 1. Stop all Terraform operations immediately

# 2. Navigate to latest backup
cd backups/terraform-state
ls -lt | head -n 2  # Find most recent

# 3. Restore state file
cd 20250106_143022  # Most recent backup
cp remote/bucket/terraform.tfstate \
   ../../environments/dev-accounts/terraform.tfstate

# 4. Verify restoration
cd ../../environments/dev-accounts
terraform state list
terraform plan  # Should show no changes

# 5. Create new backup
cd ../../
./scripts/utilities/backup-state.sh
```

### Cost Optimization Sprint

**Goal: Reduce monthly AWS spend**

```bash
# 1. Run cleanup in dry run mode
./scripts/utilities/cleanup-resources.sh > cost-report.txt

# 2. Review findings
cat cost-report.txt
# Total Potential Savings: $147.50/month

# 3. Prioritize by savings amount
# - High value: Unused load balancers ($16/mo each)
# - Medium value: Unattached volumes
# - Low value: Old snapshots (but large storage)

# 4. Execute cleanup (confirm each action)
./scripts/utilities/cleanup-resources.sh --execute

# 5. Verify savings in next billing cycle
aws ce get-cost-and-usage \
  --time-period Start=2025-01-01,End=2025-02-01 \
  --granularity MONTHLY \
  --metrics UnblendedCost
```

### Documentation Updates

**After module changes**:

```bash
# 1. Generate updated documentation
./scripts/utilities/generate-docs.sh

# 2. Review generated READMEs
find modules -name "README.md" -newer .git/COMMIT_EDITMSG

# 3. Add examples and descriptions manually
vim modules/networking/vpc/README.md
# Add usage examples, cost info, etc.

# 4. Update CHANGELOG
vim CHANGELOG.md
# Add changes under [Unreleased]

# 5. Commit documentation
git add modules/*/README.md CHANGELOG.md
git commit -m "docs: update module documentation for v1.2.0"
```

---

## Automation & Scheduling

### Cron Jobs

**Daily state backup** (2 AM):
```bash
0 2 * * * cd /path/to/project && ./scripts/utilities/backup-state.sh >> logs/backup.log 2>&1
```

**Weekly cleanup scan** (Sunday 1 AM):
```bash
0 1 * * 0 cd /path/to/project && ./scripts/utilities/cleanup-resources.sh >> logs/cleanup.log 2>&1
```

**Monthly documentation update** (1st of month, 3 AM):
```bash
0 3 1 * * cd /path/to/project && ./scripts/utilities/generate-docs.sh >> logs/docs.log 2>&1
```

### CI/CD Integration

**GitHub Actions Example**:

```yaml
name: Nightly Maintenance

on:
  schedule:
    - cron: '0 2 * * *'  # 2 AM daily
  workflow_dispatch:

jobs:
  backup-state:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActions
          aws-region: us-west-2
      
      - name: Backup Terraform State
        run: ./scripts/utilities/backup-state.sh
      
      - name: Upload Backup to S3
        run: |
          tar -czf state-backup-$(date +%Y%m%d).tar.gz backups/
          aws s3 cp state-backup-$(date +%Y%m%d).tar.gz \
            s3://backup-bucket/terraform-state/

  cleanup-scan:
    runs-on: ubuntu-latest
    if: github.event.schedule == '0 1 * * 0'  # Sunday only
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActions
          aws-region: us-west-2
      
      - name: Scan for Unused Resources
        run: |
          ./scripts/utilities/cleanup-resources.sh > cleanup-report.txt
          cat cleanup-report.txt
      
      - name: Create Issue for Review
        uses: actions/github-script@v6
        with:
          script: |
            const fs = require('fs');
            const report = fs.readFileSync('cleanup-report.txt', 'utf8');
            github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `Weekly Cleanup Report - ${new Date().toISOString().split('T')[0]}`,
              body: `\`\`\`\n${report}\n\`\`\``,
              labels: ['cost-optimization', 'automated']
            });
```

**GitLab CI Example**:

```yaml
.utilities:
  image: hashicorp/terraform:latest
  before_script:
    - apk add --no-cache aws-cli bash jq

backup-state:
  extends: .utilities
  script:
    - ./scripts/utilities/backup-state.sh
  only:
    - schedules
  artifacts:
    paths:
      - backups/
    expire_in: 30 days

cleanup-scan:
  extends: .utilities
  script:
    - ./scripts/utilities/cleanup-resources.sh
  only:
    - schedules
  artifacts:
    reports:
      - cleanup-report.txt
```

---

## Troubleshooting

### Backup Issues

**"Cannot read file from S3"**
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify S3 bucket access
aws s3 ls s3://your-state-bucket/

# Check IAM permissions for s3:GetObject
```

**"DynamoDB table not found"**
```bash
# Verify table exists
aws dynamodb describe-table --table-name terraform-locks

# Check region matches
aws dynamodb list-tables --region us-west-2
```

**"Backup directory full"**
```bash
# Check disk space
df -h

# Clean up old backups
cd backups/terraform-state
find . -type d -mtime +30 -exec rm -rf {} +

# Or compress backups
tar -czf old-backups.tar.gz */
rm -rf */
```

### Cleanup Issues

**"Cannot delete EBS volume"**
```bash
# Volume may be attached
aws ec2 describe-volumes --volume-ids vol-12345

# Check for snapshots in progress
aws ec2 describe-snapshots --owner-ids self \
  --filters Name=volume-id,Values=vol-12345

# Wait or force detach (dangerous)
aws ec2 detach-volume --volume-id vol-12345 --force
```

**"S3 bucket not empty"**
```bash
# List objects
aws s3 ls s3://bucket-name --recursive

# Empty bucket
aws s3 rm s3://bucket-name --recursive

# Delete versioned objects
aws s3api list-object-versions \
  --bucket bucket-name \
  --query 'Versions[].[Key,VersionId]' \
  --output text | while read key version; do
    aws s3api delete-object \
      --bucket bucket-name \
      --key "$key" \
      --version-id "$version"
done
```

**"Permission denied for cleanup"**
```bash
# Check IAM permissions
aws iam get-user

# Required permissions:
# - ec2:DescribeVolumes, DeleteVolume
# - ec2:DescribeSnapshots, DeleteSnapshot
# - ec2:ReleaseAddress
# - s3:DeleteObject, DeleteBucket
# - elasticloadbalancing:DeleteLoadBalancer
```

### Documentation Issues

**"Cannot parse variables.tf"**
```bash
# Check Terraform syntax
terraform fmt -check variables.tf
terraform validate

# Verify file encoding
file variables.tf  # Should be UTF-8 text

# Check for syntax errors
terraform console < /dev/null
```

**"Generated README incomplete"**
```bash
# Manually review module files
ls -la modules/category/module-name/

# Required files:
# - main.tf (checked)
# - variables.tf (checked)
# - outputs.tf (checked)
# - README.md (may need manual updates)

# Re-run generation
./scripts/utilities/generate-docs.sh
```

**"Module not found in index"**
```bash
# Check module directory structure
find modules -type d -mindepth 2 -maxdepth 2

# Regenerate index
./scripts/utilities/generate-docs.sh

# Manually add to MODULE_INDEX.md if needed
```

---

## Best Practices

### Backup Strategy
1. **Frequency**:
   - Before major changes: Always
   - Daily automated backups: Recommended
   - Before Terraform destroy: Required

2. **Retention**:
   - Daily backups: 7 days
   - Weekly backups: 4 weeks
   - Monthly backups: 1 year
   - Major releases: Permanent

3. **Storage**:
   - Keep backups in separate AWS account
   - Use S3 cross-region replication
   - Encrypt backup archives
   - Test restoration quarterly

4. **Verification**:
   - Test restore process regularly
   - Verify backup completeness
   - Check backup manifest
   - Validate state file integrity

### Cost Optimization
1. **Regular Reviews**:
   - Weekly dry runs
   - Monthly execution
   - Quarterly deep analysis
   - Annual architecture review

2. **Prioritization**:
   - High-cost unused resources first
   - Balance risk vs. savings
   - Consider business impact
   - Document decisions

3. **Automation**:
   - Automate detection
   - Manual review before deletion
   - Automated tagging for cleanup
   - Cost allocation tags

4. **Monitoring**:
   - Set up cost alerts
   - Track savings over time
   - Report to stakeholders
   - Adjust policies as needed

### Documentation
1. **Consistency**:
   - Use standard templates
   - Follow naming conventions
   - Include all required sections
   - Keep format uniform

2. **Quality**:
   - Clear descriptions
   - Working examples
   - Accurate variable docs
   - Up-to-date information

3. **Maintenance**:
   - Update with code changes
   - Review during PR process
   - Generate after releases
   - Archive old versions

4. **Automation**:
   - Auto-generate base docs
   - Manual enrichment required
   - CI/CD integration
   - Version control

---

## Related Documentation

- [Account Management Scripts](../account-management/README.md) - Account lifecycle management
- [Setup Scripts](../setup/README.md) - Initial environment setup
- [Validation Scripts](../validation/README.md) - Code quality and security
- [Main README](../../README.md) - Project overview
- [Developer Guide](../../docs/developer-guide/) - Complete developer documentation
