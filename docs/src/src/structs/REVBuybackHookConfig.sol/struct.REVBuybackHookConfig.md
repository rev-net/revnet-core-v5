# REVBuybackHookConfig
[Git Source](https://github.com/rev-net/revnet-core-v5/blob/364afaae78a8f60af2b98252dc96af1c2e4760d3/src/structs/REVBuybackHookConfig.sol)

**Notes:**
- member: dataHook The data hook to use.

- member: hookToConfigure The buyback hook to configure.

- member: poolConfigurations The pools to setup on the given buyback contract.


```solidity
struct REVBuybackHookConfig {
    IJBRulesetDataHook dataHook;
    IJBBuybackHook hookToConfigure;
    REVBuybackPoolConfig[] poolConfigurations;
}
```

