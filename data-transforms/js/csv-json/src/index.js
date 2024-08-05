import { onRecordWritten } from "@redpanda-data/transform-sdk";

onRecordWritten(csvToJsonTransform);

function csvToJsonTransform(event, writer) {
  // The input data is a CSV (without a header row) that is structured as:
  // key, item, quantity
  const input = event.record.value.text();
  const rows = input.split('\n');

  for (const row of rows) {
    const columns = row.split(',');

    if (columns.length !== 2) {
      throw new Error('unexpected number of columns');
    }

    const quantity = parseInt(columns[1], 10);
    if (isNaN(quantity)) {
      throw new Error('invalid quantity');
    }

    const itemQuantity = {
      item: columns[0],
      quantity: quantity,
    };
    event.record.value = JSON.stringify(itemQuantity);
    writer.write(event.record);
  }
}
