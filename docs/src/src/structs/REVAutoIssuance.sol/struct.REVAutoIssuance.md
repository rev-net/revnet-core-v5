# REVAutoIssuance
[Git Source](https://github.com/rev-net/revnet-core-v5/blob/364afaae78a8f60af2b98252dc96af1c2e4760d3/src/structs/REVAutoIssuance.sol)

**Notes:**
- member: chainId The ID of the chain on which the mint should be honored.

- member: count The number of tokens that should be minted.

- member: beneficiary The address that will receive the minted tokens.


```solidity
struct REVAutoIssuance {
    uint32 chainId;
    uint104 count;
    address beneficiary;
}
```

