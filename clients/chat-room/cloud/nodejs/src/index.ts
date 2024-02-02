import * as readline from "node:readline";
import * as Admin from "./admin";
import * as Producer from "./producer";
import * as Consumer from "./consumer";
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});
async function start() {
  const topic = "chat-room";
  console.log(`Creating topic: ${topic}`);
  await Admin.createTopic(topic);
  console.log("Connecting...");
  await Consumer.connect();
  rl.question("Enter user name: \n", async function (username) {
    const sendMessage = await Producer.getConnection(username);
    if (sendMessage) {
      console.log("Connected, press Ctrl+C to exit");
      rl.on("line", (input) => {
        readline.moveCursor(process.stdout, 0, -1);
        sendMessage(input);
      });
    } else {
      console.error("Failed to initialize sendMessage function");
    }
  });
}
start();
process.on("SIGINT", async () => {
  console.log('Closing app...');
  try {
    await Producer.disconnect();
    await Consumer.disconnect();
    rl.close();
  } catch (err) {
    console.error('Error during cleanup:', err);
    process.exit(1);
  } finally {
    console.log('Cleanup finished. Exiting');
    process.exit(0);
  }
});