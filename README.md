# sBTC Collateralized Loans

A peer-to-peer lending platform that enables Bitcoin-backed loans with automated collateral management and liquidation protection.

## Features

- **Loan Marketplace**: Lenders create offers with custom terms and rates
- **Collateral Management**: Secure deposit and tracking of Bitcoin collateral  
- **Automated Lending**: Streamlined loan origination with instant fund transfer
- **Repayment System**: Simple loan repayment with collateral release
- **Liquidation Protection**: Automated liquidation for overdue loans
- **Risk Assessment**: Real-time collateral ratio monitoring

## Contract Functions

### Public Functions
- `create-loan-offer()`: List loan with terms and collateral requirements
- `deposit-collateral()`: Deposit Bitcoin as loan collateral
- `take-loan()`: Accept loan offer with collateral lockup
- `repay-loan()`: Repay loan and release collateral
- `liquidate-loan()`: Liquidate overdue loan collateral
- `withdraw-collateral()`: Withdraw available collateral

### Read-Only Functions
- `get-loan-offer()`: View loan offer details
- `get-loan-info()`: Get active loan information
- `get-user-collateral()`: Check available collateral balance
- `calculate-liquidation-risk()`: Assess loan risk level

## Usage

Lenders post offers, borrowers deposit collateral and take loans, with automated systems handling repayment and liquidation scenarios.

## Risk Management

All loans require over-collateralization with automated liquidation triggers to protect lender interests and maintain system stability.