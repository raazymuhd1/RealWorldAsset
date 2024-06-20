## Real World Assets

 **3 Traits of Real World Assets**
  - a location of real world assets ( off-chain for sure )
  - a locations of a collateral assets ( on-chain / off-chain )
  - location of backer ( directly backed (off-chain, ex: usdt backed by $usd) ) and ( indirectly backed (on-chain, ex: DAI as a back assets))



**How tokenize real world assets works (on-chain collateral / indirectly backed by on-chain assets (synthetic)) ??**
  user have 10_000 laptop or 1_000 car and wanted to tokenized it, that user (assets owner) must have to deposit the collateral asset worth of 10_000 laptop (if 1 laptop = $100, that means $1000_000 needs tobe deposited) (on-chain asset like: ETH, USDT, etc) into the contract and minted 10_000 tokenized laptop in return.

  if user (real world asset owner) wants to burn the tokenized laptop, then they could just redeem it with the collateral assets ( 100 tokenized laptop = $10_000 worth of ETH, USDT, or other token as collateral)

  - things included
    - `health factor` - health factor must be above 1
    - `collateral`-  it should have a collateral, and 200% (200% from the token amount user wants to mint) collateral is best practices 
      - ex: for 1_000_000 (1 assets = $1, 1000_000 = $1000_000) tokenized assets, assets owner should deposit $2000_000 worth of collateral assets.