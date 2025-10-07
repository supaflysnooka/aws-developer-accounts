# Account Management Scripts

Scripts for managing the lifecycle of AWS developer accounts - from creation to offboarding.

## Overview

These scripts provide automated workflows for:
- Creating new developer accounts with standard configurations
- Onboarding developers with proper resources and documentation
- Offboarding developers and archiving their resources

## Scripts

### `create-account.sh`

**Purpose**: Quick account creation with minimal prompts

**Features**:
- Interactive and non-interactive modes
- Input validation (name format, email, budget)
- Wraps `onboard-developer.sh` for simplified usage
- Generates welcome documentation

**Usage**:

```bash
# Interactive mode (recommended for first-time users)
./create-account.sh

# Non-interactive mode with flags
./create-account.sh -n john-smith -e john.smith@boseprofessional.com

# With custom budget and Jira ticket
./create-account.sh -n jane-doe -e jane.doe@example.com -b 200 -j INFRA-123
```

**Options**:
- `-n, --name NAME` - Developer name (lowercase-hyphen format)
- `-e, --email EMAIL` - Developer email address
- `-b, --budget AMOUNT` - Monthly budget limit in USD (default: 100)
- `-j, --jira TICKET` - Jira ticket ID for tracking
- `-h, --help` - Show usage information

**Prerequisites**:
- AWS credentials configured (`aws configure sso`)
- Terraform installed
- jq installed
- Appropriate IAM permissions

**Output**:
- New AWS account in organization
- Generated documentation in `generated/<developer-name>/`
- Backend configuration files
- Welcome email content

---

### `onboard-developer.sh`

**Purpose**: Complete developer onboarding process with full Terraform workflow

**Features**:
- Adds developer configuration to Terraform
- Runs full Terraform plan and apply
- Generates comprehensive onboarding documentation
- Creates backend configuration files
- Provides welcome email template

**Usage**:

```bash
./onboard-developer.sh
```

The script will prompt for:
1. Developer name (lowercase, alphanumeric, hyphens)
2. Developer email address
3. Monthly budget limit (default: $100)
4. Jira ticket ID for tracking

**Workflow**:
1. **Validation** - Checks prerequisites and input format
2. **Configuration** - Updates Terraform files with developer details
3. **Planning** - Generates Terraform plan for review
4. **Approval** - Requires explicit confirmation before apply
5. **Provisioning** - Creates AWS account and resources
6. **Documentation** - Generates README and backend config
7. **Summary** - Provides next steps and manual actions

**Generated Files**:
```
generated/<developer-name>/
├── README.md              # Complete onboarding guide
└── backend.tf             # Terraform backend configuration
```

**Manual Post-Onboarding Tasks**:
1. Send welcome email to developer
2. Add developer to #aws-developer-accounts Slack channel
3. Schedule onboarding call if needed
4. Update Jira ticket status

---

### `offboard-developer.sh`

**Purpose**: Safe removal of developer accounts with data preservation

**Features**:
- Complete backup of account state and resources
- Creates final snapshots (RDS, EBS)
- Exports cost reports for the last 90 days
- Optional S3 resource cleanup
- Removes account from Terraform
- Archives all documentation

**Usage**:

```bash
./offboard-developer.sh
```

The script will prompt for:
1. Developer name to offboard
2. Confirmation to proceed
3. Confirmation for S3 cleanup
4. Final confirmation for Terraform destroy

**Workflow**:
1. **Prerequisites Check** - Verifies tools and credentials
2. **Verification** - Confirms developer account exists
3. **State Backup** - Backs up all Terraform state
4. **Snapshots** - Creates final RDS and EBS snapshots
5. **Cost Export** - Generates 90-day cost report
6. **S3 Cleanup** - Optionally empties and deletes S3 buckets
7. **Terraform Removal** - Removes account from configuration
8. **Archival** - Moves generated files to archive
9. **Report Generation** - Creates offboarding documentation

**Safety Features**:
- Multiple confirmation prompts
- Complete data backups before deletion
- 90-day recovery window for AWS account
- Detailed offboarding report

**Archive Structure**:
```
archive/<developer-name>-<timestamp>/
├── OFFBOARDING_REPORT.md  # Complete offboarding documentation
├── account_info.json       # Account metadata
├── terraform_state.json    # Terraform state backup
├── cost_report.json        # 90-day cost history
├── cost_summary.txt        # Cost summary
└── generated/              # Copy of generated documentation
```

**Post-Offboarding Tasks**:
1. Notify developer that account has been closed
2. Remove developer from #aws-developer-accounts Slack
3. Update Jira ticket to closed status
4. Review and delete snapshots after retention period
5. Archive backup directory after 90 days minimum

---

## Best Practices

### Account Naming
- Use lowercase letters, numbers, and hyphens only
- Format: `firstname-lastname` (e.g., `john-smith`)
- Keep names consistent with corporate directory

### Budget Management
- Default budget: $100/month
- Standard developer: $100-200/month
- Heavy compute workloads: $200-500/month
- Always include budget alerts at 80% and 90%

### Security
- Never share account credentials
- Use IAM roles, not IAM users
- Enable MFA for console access
- Require SSO authentication

### Documentation
- Update Jira tickets throughout the process
- Keep generated documentation current
- Document any manual changes made to accounts

### Offboarding
- Retain backups for minimum 90 days
- Review cost reports before archival
- Ensure all data is backed up or migrated
- Verify snapshots are created successfully

## Troubleshooting

### Common Issues

**"AWS credentials not configured"**
```bash
# Configure AWS SSO
aws configure sso

# Set your profile
export AWS_PROFILE=your-profile-name
```

**"Developer already exists in configuration"**
- Check if account was previously created
- Review `environments/dev-accounts/main.tf`
- Use offboard script to remove old configuration

**"Terraform plan failed"**
- Ensure Terraform is initialized: `terraform init`
- Check AWS credentials are valid
- Review error messages for specific issues

**"S3 bucket deletion failed"**
- Bucket may not be empty
- Check for versioned objects
- Manually empty bucket then retry

**"Cannot find onboard script"**
- Run from project root directory
- Verify script paths are correct
- Check file permissions: `chmod +x scripts/account-management/*.sh`

### Getting Help

- **Documentation**: Review generated README files in `generated/`
- **Infrastructure Team**: infrastructure-team@boseprofessional.com
- **Slack**: #aws-developer-accounts channel
- **Jira**: Create ticket in INFRA project

## Script Maintenance

### Updating Budget Defaults
Edit `create-account.sh` and `onboard-developer.sh`:
```bash
# Change default budget
budget=${budget:-100}  # Change 100 to new default
```

### Modifying Backup Retention
Edit `offboard-developer.sh`:
```bash
# Update retention period in offboarding report
- **Minimum**: 90 days (compliance)
- **Recommended**: 1 year
```

### Customizing Documentation
Templates are located in the scripts themselves. Look for:
```bash
cat > "$GENERATED_DIR/$dev_name/README.md" <<EOF
# Customize template here
EOF
```

## Integration with CI/CD

These scripts can be integrated into automated workflows:

```yaml
# Example GitHub Actions workflow
- name: Create Developer Account
  run: |
    ./scripts/account-management/create-account.sh \
      -n ${{ inputs.developer_name }} \
      -e ${{ inputs.developer_email }} \
      -b ${{ inputs.budget }} \
      -j ${{ inputs.jira_ticket }}
```

## Related Documentation

- [Setup Scripts](../setup/README.md) - Environment bootstrap and configuration
- [Validation Scripts](../validation/README.md) - Code quality and security checks
- [Utilities Scripts](../utilities/README.md) - Helper tools and maintenance
- [Main README](../../README.md) - Project overview
- [Developer Guide](../../docs/developer-guide/) - Complete developer documentation
