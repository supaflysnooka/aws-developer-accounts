# Set profile
export AWS_PROFILE=AdministratorAccess-816648956019

# Verify
aws sts get-caller-identity

# Should show:
# Account: 816648956019
# Role: AdministratorAccess

# Try Terraform
cd environments/dev-accounts
tf init
