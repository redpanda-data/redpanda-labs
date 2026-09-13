import { redpanda } from "./config";

// tag::admin[]
const admin = redpanda.admin();

// Create the topic if it does not exist yet (one partition, one replica).
export async function createTopic(topic: string, partitions = 1, replicas = 1) {
  await admin.connect();
  try {
    const existingTopics = await admin.listTopics();
    if (!existingTopics.includes(topic)) {
      await admin.createTopics({
        topics: [{ topic, numPartitions: partitions, replicationFactor: replicas }],
      });
      console.log(`Created topic ${topic}`);
    }
  } finally {
    await admin.disconnect();
  }
}
// end::admin[]
