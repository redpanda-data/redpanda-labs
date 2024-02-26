import chalk from "chalk";
import csv from "csv-parser";
import parseArgs from "minimist";
import path from "path";
import { addDays } from "date-fns";
import { createReadStream } from "fs";
import { Kafka } from "kafkajs";

let args = parseArgs(process.argv.slice(2));
const help = `
  ${chalk.red("producer.js")} - produce events to an event bus by reading data from csv file

  ${chalk.bold("USAGE")}

  > node producer.js --help
  > node producer.js [-f path_to_file] [-t topic_name] [-b host:port] [-d date_column_name] [-r] [-l]

  By default the producer script will stream data from market_activity.csv and output events to topic market_activity.

  If either the loop or reverse arguments are given, file content is read into memory prior to sending events.
  Don't use the loop/reverse arguments if the file size is large or your system memory capacity is low.

  ${chalk.bold("OPTIONS")}

      -h, --help                  Shows this help message

      -f, --file, --csv           Reads from file and outputs events to a topic named after the file
                                    default: ../../spark/scala/src/main/resources/market_activity.csv

      -t, --topic                 Topic where events are sent
                                    default: market_activity

      -b, --broker --brokers      Comma-separated list of the host and port for each broker
                                    default: localhost:9092

      -d, --date                  Date is turned into an ISO string and incremented during loop
                                    default: Date

      -r, --reverse               Read file into memory and then reverse

      -l, --loop                  Read file into memory and then loop continuously

  ${chalk.bold("EXAMPLES")}

      Stream data from default file and output events to default topic on default broker:

          > node producer.js

      Stream data from data.csv and output to a topic named data on broker at brokerhost.dev port 19092:

          > node producer.js -f data.csv -b brokerhost.dev:19092

      Read data from default file and output events to default topic on broker at localhost port 19092:

          > node producer.js --brokers localhost:19092

      Read data from default file into memory, reverse contents, and send events to default topic on broker at localhost port 19092:

          > node producer.js -rb localhost:19092

      Read data from default file into memory, reverse contents, output ISO date string for Date prop:

        > node producer.js --brokers localhost:19092 --reverse --date Date

      Same as above, but loop continuously and increment the date by one day on each event:

        > node producer.js -lrb localhost:19092 -d Date
`;

if (args.help || args.h) {
  console.log(help);
  process.exit(0);
}

const brokers = (args.brokers || args.b || "localhost:9092").split(",");
const csvPath =
  args.csv || args.file || args.f || "../../spark/scala/src/main/resources/market_activity.csv";
const topic =
  args.topic || args.t || path.basename(csvPath, ".csv") || path.basename(csvPath, ".CSV");
const dateProp = args.date || args.d;
const isReverse = args.reverse || args.r;
const isLoop = args.loop || args.l;

const redpanda = new Kafka({
  clientId: "example-producer-js",
  brokers,
});
const producer = redpanda.producer();

/* Produce single message */
const send = async (obj) => {
  try {
    const json = JSON.stringify(obj);
    await producer.send({
      topic: topic,
      messages: [{ value: json }],
    });
    console.log(`Produced: ${json}`);
  } catch (e) {
    console.error(e);
  }
};

const run = async () => {
  let lastDate;
  console.log("Producer connecting...");
  await producer.connect();
  let data = [];
  // Transform each CSV row as JSON and send to Redpanda
  createReadStream(csvPath)
    .pipe(csv())
    .on("data", function (row) {
      if (dateProp) {
        if (!row[dateProp]) {
          throw new Error("Invalid date argument (-d, --date). Must match an existing column.");
        }
        row[dateProp] = new Date(row[dateProp]);
      }
      if (isLoop || isReverse) {
        // set last date if we have a date prop, and either if 1) we are on the first entry while reversed or 2) not reversed
        if (dateProp && ((isReverse && !lastDate) || !isReverse)) lastDate = row[dateProp];
        data.push(row);
      } else {
        send(row);
      }
    })
    .on("end", async function () {
      if (isLoop || isReverse) {
        if (isReverse) data.reverse();
        for (let i = 0; i < data.length; i++) {
          await send(data[i]);
        }
        while (isLoop) {
          for (let i = 0; i < data.length; i++) {
            if (dateProp) data[i][dateProp] = lastDate = addDays(lastDate, 1);
            await send(data[i]);
          }
        }
      }
    });
};
run().catch((e) => console.error(e));

/* Disconnect on CTRL+C */
process.on("SIGINT", async () => {
  try {
    console.log("\nProducer disconnecting...");
    await producer.disconnect();
    process.exit(0);
  } catch (_) {
    process.exit(1);
  }
});
