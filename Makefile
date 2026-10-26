.PHONY: test invariant assets deploy fmt

test:
	forge test -vvv

invariant:
	forge test --match-contract SeriesInvariantTest -vvv

assets:
	set -a; . ./.env; set +a; forge script script/CheckMezoAssets.s.sol:CheckMezoAssets --rpc-url "$$MEZO_TESTNET_RPC_URL" -vvvv

deploy:
	set -a; . ./.env; set +a; forge script script/DeploySeries.s.sol:DeploySeries --rpc-url "$$MEZO_TESTNET_RPC_URL" --broadcast -vvvv

fmt:
	forge fmt
