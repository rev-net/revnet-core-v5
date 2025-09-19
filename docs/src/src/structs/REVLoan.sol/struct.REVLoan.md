# REVLoan
[Git Source](https://github.com/rev-net/revnet-core-v5/blob/364afaae78a8f60af2b98252dc96af1c2e4760d3/src/structs/REVLoan.sol)

**Notes:**
- member: borrowedAmount The amount that is being borrowed.

- member: collateralTokenCount The number of collateral tokens currently accounted for.

- member: createdAt The timestamp when the loan was created.

- member: prepaidFeePercent The percentage of the loan's fees that were prepaid.

- member: prepaidDuration The duration that the loan was prepaid for.

- member: source The source of the loan.


```solidity
struct REVLoan {
    uint112 amount;
    uint112 collateral;
    uint48 createdAt;
    uint16 prepaidFeePercent;
    uint32 prepaidDuration;
    REVLoanSource source;
}
```

