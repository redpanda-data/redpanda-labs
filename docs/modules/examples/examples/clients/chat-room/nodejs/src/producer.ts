import { redpanda, topic } from "./config";

// tag::producer[]
const producer = redpanda.producer();

// Connect once and return a function that sends one JSON-encoded chat message.
export async function getConnection(user: string) {
  await producer.connect();
  return async (message: string) => {
    await producer.send({
      topic,
      messages: [{ value: JSON.stringify({ user, message }) }],
    });
  };
}
// end::producer[]

export async function disconnect() {
  await producer.disconnect();
}
