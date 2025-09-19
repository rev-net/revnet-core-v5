# REVCroptopAllowedPost
[Git Source](https://github.com/rev-net/revnet-core-v5/blob/364afaae78a8f60af2b98252dc96af1c2e4760d3/src/structs/REVCroptopAllowedPost.sol)

Criteria for allowed posts.

**Notes:**
- member: category A category that should allow posts.

- member: minimumPrice The minimum price that a post to the specified category should cost.

- member: minimumTotalSupply The minimum total supply of NFTs that can be made available when minting.

- member: maxTotalSupply The max total supply of NFTs that can be made available when minting. Leave as 0 for
max.

- member: allowedAddresses A list of addresses that are allowed to post on the category through Croptop.


```solidity
struct REVCroptopAllowedPost {
    uint24 category;
    uint104 minimumPrice;
    uint32 minimumTotalSupply;
    uint32 maximumTotalSupply;
    address[] allowedAddresses;
}
```

