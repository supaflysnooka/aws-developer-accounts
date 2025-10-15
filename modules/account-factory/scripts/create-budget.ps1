# modules/account-factory/scripts/create-budget.ps1
# Create AWS budget with alerts

$ErrorActionPreference = "Stop"

$AccountId = "${account_id}"
$DeveloperName = "${developer_name}"
$BudgetLimit = "${budget_limit}"
$DeveloperEmail = "${developer_email}"
$AdminEmail = "${admin_email}"

Write-Host "Creating budget..." -ForegroundColor Cyan

try {
    # Budget definition
    $Budget = @{
        BudgetName = "bose-dev-$DeveloperName-monthly-budget"
        BudgetType = "COST"
        TimeUnit = "MONTHLY"
        BudgetLimit = @{
            Amount = $BudgetLimit
            Unit = "USD"
        }
        CostFilters = @{
            LinkedAccount = @($AccountId)
        }
    } | ConvertTo-Json -Depth 10
    
    # Notifications
    $Notifications = @(
        @{
            Notification = @{
                NotificationType = "ACTUAL"
                ComparisonOperator = "GREATER_THAN"
                Threshold = 80
                ThresholdType = "PERCENTAGE"
            }
            Subscribers = @(
                @{
                    SubscriptionType = "EMAIL"
                    Address = $DeveloperEmail
                },
                @{
                    SubscriptionType = "EMAIL"
                    Address = $AdminEmail
                }
            )
        },
        @{
            Notification = @{
                NotificationType = "FORECASTED"
                ComparisonOperator = "GREATER_THAN"
                Threshold = 90
                ThresholdType = "PERCENTAGE"
            }
            Subscribers = @(
                @{
                    SubscriptionType = "EMAIL"
                    Address = $DeveloperEmail
                },
                @{
                    SubscriptionType = "EMAIL"
                    Address = $AdminEmail
                }
            )
        }
    ) | ConvertTo-Json -Depth 10
    
    # Save to temp files
    $BudgetFile = [System.IO.Path]::GetTempFileName()
    $NotificationsFile = [System.IO.Path]::GetTempFileName()
    
    $Budget | Out-File -FilePath $BudgetFile -Encoding UTF8
    $Notifications | Out-File -FilePath $NotificationsFile -Encoding UTF8
    
    # Create budget
    aws budgets create-budget `
        --account-id $AccountId `
        --budget "file://$BudgetFile" `
        --notifications-with-subscribers "file://$NotificationsFile" 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Budget may already exist" -ForegroundColor Yellow
    } else {
        Write-Host "Budget created successfully" -ForegroundColor Green
    }
    
    # Clean up
    Remove-Item $BudgetFile -ErrorAction SilentlyContinue
    Remove-Item $NotificationsFile -ErrorAction SilentlyContinue
    
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
