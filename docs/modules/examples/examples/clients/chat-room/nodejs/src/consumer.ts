import { randomUUID } from "node:crypto";
import { redpanda, topic } from "./config";

// tag::consumer[]
// Each run joins a new consumer group and reads from the beginning of the
// topic, so every client sees the whole chat history.
const consumer = redpanda.consumer({
  kafkaJS: { groupId: randomUUID(), fromBeginning: true },
});

export async function connect() {
  await consumer.connect();
  await consumer.subscribe({ topics: [topic] });
  await consumer.run({
    eachMessage: async ({ message }) => {
      const { user, message: text } = JSON.parse(message.value!.toString());
      console.log(`${user}: ${text}`);
    },
  });
}
// end::consumer[]

export async function disconnect() {
  await consumer.disconnect();
}
