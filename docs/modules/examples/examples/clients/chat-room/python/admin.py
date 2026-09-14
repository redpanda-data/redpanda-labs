from kafka.admin import KafkaAdminClient, NewTopic

from config import client_config


# tag::admin[]
class ChatAdmin:
    def __init__(self):
        self.admin = KafkaAdminClient(**client_config())

    def topic_exists(self, topic_name):
        return topic_name in self.admin.list_topics()

    def create_topic(self, topic_name, num_partitions=1, replication_factor=1):
        """Create the topic with one partition and one replica."""
        if self.topic_exists(topic_name):
            print(f"Topic {topic_name} already exists.")
            return
        self.admin.create_topics(
            [NewTopic(name=topic_name, num_partitions=num_partitions, replication_factor=replication_factor)]
        )
        print(f"Topic {topic_name} created.")
# end::admin[]

    def close(self):
        self.admin.close()
