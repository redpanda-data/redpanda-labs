// src/index.js
import { onRecordWritten } from "@redpanda-data/transform-sdk";
onRecordWritten(csvToJsonTransform);
function csvToJsonTransform(event, writer) {
  const input = event.record.value.text();
  const rows = input.split("\n");
  console.log(rows);
  for (const row of rows) {
    const columns = row.split(",");
    console.log(columns);
    if (columns.length !== 2) {
      throw new Error("unexpected number of columns");
    }
    const quantity = parseInt(columns[1], 10);
    if (isNaN(quantity)) {
      throw new Error("invalid quantity");
    }
    const itemQuantity = {
      item: columns[0],
      quantity
    };
    event.record.value = JSON.stringify(itemQuantity);
    writer.write(event.record);
  }
}
