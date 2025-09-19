# REVLoanSource
[Git Source](https://github.com/rev-net/revnet-core-v5/blob/364afaae78a8f60af2b98252dc96af1c2e4760d3/src/structs/REVLoanSource.sol)

**Notes:**
- member: token The token that is being loaned.

- member: terminal The terminal that the loan is being made from.


```solidity
struct REVLoanSource {
    address token;
    IJBPayoutTerminal terminal;
}
```

