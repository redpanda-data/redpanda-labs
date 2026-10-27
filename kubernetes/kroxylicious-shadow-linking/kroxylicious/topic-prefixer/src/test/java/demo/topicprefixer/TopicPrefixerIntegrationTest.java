package demo.topicprefixer;

import java.time.Duration;
import java.util.List;
import java.util.Map;

import io.kroxylicious.kafka.common.message.ListGroupsResponseData;
import io.kroxylicious.kafka.common.message.MetadataResponseData;
import io.kroxylicious.kafka.common.message.ResponseHeaderData;
import io.kroxylicious.testing.filter.assertj.MockFilterContextAssert;
import io.kroxylicious.testing.filter.context.MockFilterContext;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Exercises the full path from {@link TopicPrefixerConfig} through {@link TopicPrefixer#initialize}
 * and {@link TopicPrefixer#createFilter} to the resulting filter's behaviour, to prove topics and
 * consumer groups really can be configured - and renamed - independently of one another.
 */
class TopicPrefixerIntegrationTest {

    private static final short METADATA_VERSION = 12;
    private static final short LIST_GROUPS_VERSION = 4;

    @Test
    void topicsAndGroupsCanUseIndependentPrefixes() {
        var config = new TopicPrefixerConfig(new RenamingConfig("p_", null), new RenamingConfig("g_", null));
        var filter = buildFilter(config);

        assertThat(renamedTopicName(filter, "foo")).isEqualTo("p_foo");
        assertThat(renamedGroupId(filter, "my-group")).isEqualTo("g_my-group");
    }

    @Test
    void topicsAndGroupsCanUseIndependentMappings() {
        var config = new TopicPrefixerConfig(
                new RenamingConfig(null, Map.of("foo", "renamed-topic")),
                new RenamingConfig(null, Map.of("my-group", "renamed-group")));
        var filter = buildFilter(config);

        assertThat(renamedTopicName(filter, "foo")).isEqualTo("renamed-topic");
        assertThat(renamedGroupId(filter, "my-group")).isEqualTo("renamed-group");
    }

    @Test
    void topicsAndGroupsCanMixStrategies() {
        var config = new TopicPrefixerConfig(new RenamingConfig("p_", null), new RenamingConfig(null, Map.of("my-group", "renamed-group")));
        var filter = buildFilter(config);

        assertThat(renamedTopicName(filter, "foo")).isEqualTo("p_foo");
        assertThat(renamedGroupId(filter, "my-group")).isEqualTo("renamed-group");
    }

    private static TopicPrefixerFilter buildFilter(TopicPrefixerConfig config) {
        var topicPrefixer = new TopicPrefixer();
        var renamers = topicPrefixer.initialize(null, config);
        return topicPrefixer.createFilter(null, renamers);
    }

    private static String renamedTopicName(TopicPrefixerFilter filter, String realName) {
        var header = new ResponseHeaderData();
        var response = new MetadataResponseData();
        var topic = new MetadataResponseData.MetadataResponseTopic();
        topic.setName(realName);
        response.setTopics(new MetadataResponseData.MetadataResponseTopicCollection(List.of(topic).iterator()));
        var context = MockFilterContext.builder(header, response).build();

        var stage = filter.onMetadataResponse(METADATA_VERSION, header, response, context);

        var box = new String[1];
        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardResponse()
                .hasMessageInstanceOfSatisfying(MetadataResponseData.class,
                        forwarded -> box[0] = forwarded.topics().iterator().next().name()));
        return box[0];
    }

    private static String renamedGroupId(TopicPrefixerFilter filter, String realGroupId) {
        var header = new ResponseHeaderData();
        var response = new ListGroupsResponseData();
        var group = new ListGroupsResponseData.ListedGroup();
        group.setGroupId(realGroupId);
        response.setGroups(List.of(group));
        var context = MockFilterContext.builder(header, response).build();

        var stage = filter.onListGroupsResponse(LIST_GROUPS_VERSION, header, response, context);

        var box = new String[1];
        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardResponse()
                .hasMessageInstanceOfSatisfying(ListGroupsResponseData.class,
                        forwarded -> box[0] = forwarded.groups().get(0).groupId()));
        return box[0];
    }
}
