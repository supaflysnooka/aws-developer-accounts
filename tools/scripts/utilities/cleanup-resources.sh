#!/bin/bash

# Resource Cleanup Script
# Identifies and removes unused AWS resources to reduce costs

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SAVINGS=0
DRY_RUN=true

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    print_success "AWS credentials configured"
}

find_unused_eips() {
    print_header "Finding Unused Elastic IPs"
    
    local unused_eips=$(aws ec2 describe-addresses \
        --query 'Addresses[?AssociationId==`null`].[PublicIp,AllocationId]' \
        --output text 2>/dev/null)
    
    if [ -z "$unused_eips" ]; then
        print_success "No unused Elastic IPs found"
        return
    fi
    
    local count=$(echo "$unused_eips" | wc -l)
    local monthly_cost=$(echo "$count * 3.65" | bc)
    
    print_warning "Found $count unused Elastic IP(s)"
    echo "$unused_eips" | while read ip allocation_id; do
        echo "  $ip ($allocation_id)"
    done
    
    printf "Potential savings: \$%.2f/month\n" $monthly_cost
    SAVINGS=$(echo "$SAVINGS + $monthly_cost" | bc)
    
    if [ "$DRY_RUN" = false ]; then
        read -p "Release unused Elastic IPs? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            echo "$unused_eips" | while read ip allocation_id; do
                print_info "Releasing $ip..."
                aws ec2 release-address --allocation-id "$allocation_id"
            done
            print_success "Released $count Elastic IP(s)"
        fi
    fi
}

find_unattached_volumes() {
    print_header "Finding Unattached EBS Volumes"
    
    local volumes=$(aws ec2 describe-volumes \
        --filters Name=status,Values=available \
        --query 'Volumes[].[VolumeId,Size,VolumeType,CreateTime]' \
        --output text 2>/dev/null)
    
    if [ -z "$volumes" ]; then
        print_success "No unattached volumes found"
        return
    fi
    
    local count=$(echo "$volumes" | wc -l)
    local total_gb=0
    
    print_warning "Found $count unattached volume(s):"
    echo "$volumes" | while read vol_id size vol_type create_time; do
        echo "  $vol_id - ${size}GB $vol_type (created: $create_time)"
        total_gb=$((total_gb + size))
    done
    
    # gp3: $0.08/GB/month
    local monthly_cost=$(echo "$total_gb * 0.08" | bc)
    printf "Potential savings: \$%.2f/month\n" $monthly_cost
    SAVINGS=$(echo "$SAVINGS + $monthly_cost" | bc)
    
    if [ "$DRY_RUN" = false ]; then
        read -p "Delete unattached volumes? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            echo "$volumes" | while read vol_id size vol_type create_time; do
                print_info "Creating snapshot of $vol_id before deletion..."
                snapshot_id=$(aws ec2 create-snapshot \
                    --volume-id "$vol_id" \
                    --description "Backup before cleanup on $(date)" \
                    --query 'SnapshotId' --output text)
                print_info "Snapshot created: $snapshot_id"
                
                print_info "Deleting $vol_id..."
                aws ec2 delete-volume --volume-id "$vol_id"
            done
            print_success "Deleted $count volume(s)"
        fi
    fi
}

find_old_snapshots() {
    print_header "Finding Old EBS Snapshots"
    
    # Find snapshots older than 90 days
    local cutoff_date=$(date -d '90 days ago' +%Y-%m-%d)
    
    local snapshots=$(aws ec2 describe-snapshots \
        --owner-ids self \
        --query "Snapshots[?StartTime<'$cutoff_date'].[SnapshotId,VolumeSize,StartTime,Description]" \
        --output text 2>/dev/null)
    
    if [ -z "$snapshots" ]; then
        print_success "No old snapshots found"
        return
    fi
    
    local count=$(echo "$snapshots" | wc -l)
    local total_gb=0
    
    print_warning "Found $count snapshot(s) older than 90 days:"
    echo "$snapshots" | while read snap_id size start_time description; do
        echo "  $snap_id - ${size}GB (created: $start_time)"
        total_gb=$((total_gb + size))
    done
    
    # Snapshot storage: $0.05/GB/month
    local monthly_cost=$(echo "$total_gb * 0.05" | bc)
    printf "Potential savings: \$%.2f/month\n" $monthly_cost
    SAVINGS=$(echo "$SAVINGS + $monthly_cost" | bc)
    
    if [ "$DRY_RUN" = false ]; then
        read -p "Delete old snapshots? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            echo "$snapshots" | while read snap_id size start_time description; do
                print_info "Deleting $snap_id..."
                aws ec2 delete-snapshot --snapshot-id "$snap_id"
            done
            print_success "Deleted $count snapshot(s)"
        fi
    fi
}

find_unused_amis() {
    print_header "Finding Unused AMIs"
    
    local amis=$(aws ec2 describe-images \
        --owners self \
        --query 'Images[].[ImageId,Name,CreationDate]' \
        --output text 2>/dev/null)
    
    if [ -z "$amis" ]; then
        print_success "No custom AMIs found"
        return
    fi
    
    local unused_count=0
    
    echo "$amis" | while read ami_id name created; do
        # Check if AMI is used by any instance or launch template
        local in_use=$(aws ec2 describe-instances \
            --filters "Name=image-id,Values=$ami_id" \
            --query 'Reservations[].Instances[].InstanceId' \
            --output text 2>/dev/null)
        
        if [ -z "$in_use" ]; then
            echo "  $ami_id - $name (unused, created: $created)"
            unused_count=$((unused_count + 1))
        fi
    done
    
    if [ $unused_count -eq 0 ]; then
        print_success "All AMIs are in use"
    else
        print_warning "Found $unused_count unused AMI(s)"
        print_info "Consider deregistering unused AMIs and deleting their snapshots"
    fi
}

find_incomplete_multipart_uploads() {
    print_header "Finding Incomplete S3 Multipart Uploads"
    
    local buckets=$(aws s3 ls | awk '{print $3}')
    local total_count=0
    
    for bucket in $buckets; do
        local uploads=$(aws s3api list-multipart-uploads \
            --bucket "$bucket" \
            --query 'Uploads[].[Key,Initiated]' \
            --output text 2>/dev/null)
        
        if [ -n "$uploads" ]; then
            local count=$(echo "$uploads" | wc -l)
            total_count=$((total_count + count))
            
            print_warning "Bucket: $bucket - $count incomplete upload(s)"
        fi
    done
    
    if [ $total_count -eq 0 ]; then
        print_success "No incomplete multipart uploads found"
        return
    fi
    
    print_warning "Found $total_count incomplete upload(s) total"
    print_info "These can consume storage without appearing in bucket metrics"
    
    if [ "$DRY_RUN" = false ]; then
        read -p "Abort incomplete uploads? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            for bucket in $buckets; do
                aws s3api list-multipart-uploads --bucket "$bucket" \
                    --query 'Uploads[].[Key,UploadId]' --output text 2>/dev/null | \
                while read key upload_id; do
                    if [ -n "$key" ]; then
                        print_info "Aborting upload: $bucket/$key"
                        aws s3api abort-multipart-upload \
                            --bucket "$bucket" \
                            --key "$key" \
                            --upload-id "$upload_id" 2>/dev/null
                    fi
                done
            done
            print_success "Aborted incomplete uploads"
        fi
    fi
}

find_old_cloudwatch_logs() {
    print_header "Finding Old CloudWatch Log Groups"
    
    # Find log groups without retention policy
    local log_groups=$(aws logs describe-log-groups \
        --query 'logGroups[?!retentionInDays].[logGroupName,storedBytes]' \
        --output text 2>/dev/null)
    
    if [ -z "$log_groups" ]; then
        print_success "All log groups have retention policies"
        return
    fi
    
    local count=$(echo "$log_groups" | wc -l)
    print_warning "Found $count log group(s) without retention policy:"
    
    echo "$log_groups" | while read name bytes; do
        local mb=$(echo "$bytes / 1048576" | bc)
        echo "  $name - ${mb}MB"
    done
    
    print_info "Set retention policies to automatically expire old logs"
    
    if [ "$DRY_RUN" = false ]; then
        read -p "Set 30-day retention on these log groups? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            echo "$log_groups" | while read name bytes; do
                print_info "Setting retention on $name..."
                aws logs put-retention-policy \
                    --log-group-name "$name" \
                    --retention-in-days 30 2>/dev/null
            done
            print_success "Retention policies set"
        fi
    fi
}

find_unused_load_balancers() {
    print_header "Finding Unused Load Balancers"
    
    # Find ALBs with no registered targets
    local albs=$(aws elbv2 describe-load-balancers \
        --query 'LoadBalancers[].[LoadBalancerArn,LoadBalancerName]' \
        --output text 2>/dev/null)
    
    local unused_count=0
    
    echo "$albs" | while read arn name; do
        local target_groups=$(aws elbv2 describe-target-groups \
            --load-balancer-arn "$arn" \
            --query 'TargetGroups[].TargetGroupArn' \
            --output text 2>/dev/null)
        
        local has_targets=false
        for tg in $target_groups; do
            local targets=$(aws elbv2 describe-target-health \
                --target-group-arn "$tg" \
                --query 'TargetHealthDescriptions[]' \
                --output text 2>/dev/null)
            
            if [ -n "$targets" ]; then
                has_targets=true
                break
            fi
        done
        
        if [ "$has_targets" = false ]; then
            echo "  $name (no healthy targets)"
            unused_count=$((unused_count + 1))
        fi
    done
    
    if [ $unused_count -eq 0 ]; then
        print_success "All load balancers have targets"
    else
        local monthly_cost=$(echo "$unused_count * 16.20" | bc)
        print_warning "Found $unused_count potentially unused load balancer(s)"
        printf "Potential savings: \$%.2f/month\n" $monthly_cost
        SAVINGS=$(echo "$SAVINGS + $monthly_cost" | bc)
    fi
}

find_stopped_instances() {
    print_header "Finding Stopped EC2 Instances"
    
    local stopped=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=stopped" \
        --query 'Reservations[].Instances[].[InstanceId,InstanceType,StateTransitionReason]' \
        --output text 2>/dev/null)
    
    if [ -z "$stopped" ]; then
        print_success "No stopped instances found"
        return
    fi
    
    local count=$(echo "$stopped" | wc -l)
    print_warning "Found $count stopped instance(s):"
    echo "$stopped"
    
    print_info "Stopped instances still incur EBS storage charges"
    print_info "Consider terminating if no longer needed"
}

find_unused_security_groups() {
    print_header "Finding Unused Security Groups"
    
    local all_sgs=$(aws ec2 describe-security-groups \
        --query 'SecurityGroups[].[GroupId,GroupName]' \
        --output text 2>/dev/null)
    
    local unused_count=0
    
    echo "$all_sgs" | while read sg_id sg_name; do
        # Skip default security groups
        if [[ "$sg_name" == "default" ]]; then
            continue
        fi
        
        # Check if SG is attached to anything
        local in_use=$(aws ec2 describe-network-interfaces \
            --filters "Name=group-id,Values=$sg_id" \
            --query 'NetworkInterfaces[].NetworkInterfaceId' \
            --output text 2>/dev/null)
        
        if [ -z "$in_use" ]; then
            echo "  $sg_id - $sg_name"
            unused_count=$((unused_count + 1))
        fi
    done
    
    if [ $unused_count -eq 0 ]; then
        print_success "All security groups are in use"
    else
        print_warning "Found $unused_count unused security group(s)"
        print_info "Safe to delete if confirmed not in use"
    fi
}

generate_cleanup_report() {
    print_header "Cleanup Summary"
    
    echo ""
    printf "${GREEN}Total Potential Savings: \$%.2f/month${NC}\n" $SAVINGS
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN MODE - No resources were deleted"
        print_info "Run with --execute flag to perform cleanup"
    else
        print_success "Cleanup complete"
    fi
    
    echo ""
    print_info "Additional Cleanup Recommendations:"
    echo "  1. Review and delete old Terraform state versions in S3"
    echo "  2. Clean up unused Lambda function versions"
    echo "  3. Delete old ECR images"
    echo "  4. Review CloudWatch metric filters and alarms"
    echo "  5. Check for unused Secrets Manager secrets"
}

main() {
    print_header "AWS Resource Cleanup Tool"
    
    # Parse arguments
    if [[ "$*" == *"--execute"* ]]; then
        DRY_RUN=false
        print_warning "EXECUTE MODE - Resources will be deleted"
    else
        print_info "DRY RUN MODE - No resources will be deleted"
    fi
    
    echo ""
    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    check_prerequisites
    
    # Run cleanup checks
    find_unused_eips
    find_unattached_volumes
    find_old_snapshots
    find_unused_amis
    find_incomplete_multipart_uploads
    find_old_cloudwatch_logs
    find_unused_load_balancers
    find_stopped_instances
    find_unused_security_groups
    
    # Generate report
    generate_cleanup_report
}

main "$@"
