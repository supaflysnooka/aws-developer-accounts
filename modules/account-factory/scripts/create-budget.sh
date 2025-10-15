#!/bin/bash
# modules/account-factory/scripts/create-budget.sh
# Create AWS budget with alerts

set -e

ACCOUNT_ID="${account_id}"
DEVELOPER_NAME="${developer_name}"
BUDGET_LIMIT="${budget_limit}"
DEVELOPER_EMAIL="${developer_email}"
ADMIN_EMAIL="${admin_email}"

echo "Creating budget..."

cat > /tmp/budget-$DEVELOPER_NAME.json << BUDGET
{
  "BudgetName": "bose-dev-$DEVELOPER_NAME-monthly-budget",
  "BudgetType": "COST",
  "TimeUnit": "MONTHLY",
  "BudgetLimit": {
    "Amount": "$BUDGET_LIMIT",
    "Unit": "USD"
  },
  "CostFilters": {
    "LinkedAccount": ["$ACCOUNT_ID"]
  }
}
BUDGET

cat > /tmp/notifications-$DEVELOPER_NAME.json << NOTIF
[
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "EMAIL",
        "Address": "$DEVELOPER_EMAIL"
      },
      {
        "SubscriptionType": "EMAIL",
        "Address": "$ADMIN_EMAIL"
      }
    ]
  },
  {
    "Notification": {
      "NotificationType": "FORECASTED",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 90,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "EMAIL",
        "Address": "$DEVELOPER_EMAIL"
      },
      {
        "SubscriptionType": "EMAIL",
        "Address": "$ADMIN_EMAIL"
      }
    ]
  }
]
NOTIF

# Disable exit on error temporarily
set +e
aws budgets create-budget \
  --account-id $ACCOUNT_ID \
  --budget file:///tmp/budget-$DEVELOPER_NAME.json \
  --notifications-with-subscribers file:///tmp/notifications-$DEVELOPER_NAME.json 2>&1 >/dev/null

if [ $? -ne 0 ]; then
  echo "  Budget may already exist, continuing..."
else
  echo "  Budget created successfully"
fi
set -e

rm /tmp/budget-$DEVELOPER_NAME.json
rm /tmp/notifications-$DEVELOPER_NAME.json

echo "Budget configuration complete!"