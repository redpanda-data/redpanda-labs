The data used in the client examples was downloaded from the Nasdaq historical data site: https://www.nasdaq.com/market-activity/quotes/historical. The historical stock prices and volumes are provided in CSV format, for example:

```csv
Date,Close/Last,Volume,Open,High,Low
10/18/2023,$93.75,4110651,$93.94,$94.53,$93.50
10/17/2023,$94.18,6086690,$92.75,$94.19,$92.6315
10/16/2023,$93.65,4595886,$92.17,$93.855,$91.85
10/13/2023,$91.48,4780570,$91.28,$92.06,$91.05
```

## Protobuf

To recompile the `.proto` file:

```shell
cd clients/stock-market-activity/python
protoc -I=../data --python_out=./schema_registry --pyi_out=./schema_registry ../data/*.proto
```