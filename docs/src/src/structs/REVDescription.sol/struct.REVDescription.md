# REVDescription
[Git Source](https://github.com/rev-net/revnet-core-v5/blob/364afaae78a8f60af2b98252dc96af1c2e4760d3/src/structs/REVDescription.sol)

**Notes:**
- member: name The name of the ERC-20 token being create for the revnet.

- member: ticker The ticker of the ERC-20 token being created for the revnet.

- member: uri The metadata URI containing revnet's info.

- member: salt Revnets deployed across chains by the same address with the same salt will have the same
address.


```solidity
struct REVDescription {
    string name;
    string ticker;
    string uri;
    bytes32 salt;
}
```

