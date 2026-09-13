import * as readline from "node:readline";
import * as Admin from "./admin";
import * as Producer from "./producer";
import * as Consumer from "./consumer";
import { topic } from "./config";

// tag::main[]
const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

async function start() {
  await Admin.createTopic(topic);
  console.log("Connecting...");
  await Consumer.connect();
  rl.question("Enter user name: \n", async (username) => {
    const sendMessage = await Producer.getConnection(username);
    console.log("Connected, press Ctrl+C to exit");
    rl.on("line", (input) => {
      readline.moveCursor(process.stdout, 0, -1);
      if (input.trim()) sendMessage(input);
    });
  });
}

start().catch((err) => {
  console.error(err);
  process.exit(1);
});
// end::main[]

process.on("SIGINT", async () => {
  console.log("Closing app...");
  try {
    await Producer.disconnect();
    await Consumer.disconnect();
    rl.close();
  } finally {
    process.exit(0);
  }
});
