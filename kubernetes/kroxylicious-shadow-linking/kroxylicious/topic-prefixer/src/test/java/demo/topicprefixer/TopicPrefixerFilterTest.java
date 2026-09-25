package demo.topicprefixer;

import java.time.Duration;
import java.util.List;

import io.kroxylicious.kafka.common.message.DescribeConfigsRequestData;
import io.kroxylicious.kafka.common.message.DescribeConfigsResponseData;
import io.kroxylicious.kafka.common.message.FetchRequestData;
import io.kroxylicious.kafka.common.message.FetchResponseData;
import io.kroxylicious.kafka.common.message.FindCoordinatorRequestData;
import io.kroxylicious.kafka.common.message.FindCoordinatorResponseData;
import io.kroxylicious.kafka.common.message.JoinGroupRequestData;
import io.kroxylicious.kafka.common.message.ListGroupsResponseData;
import io.kroxylicious.kafka.common.message.MetadataRequestData;
import io.kroxylicious.kafka.common.message.MetadataResponseData;
import io.kroxylicious.kafka.common.message.OffsetFetchRequestData;
import io.kroxylicious.kafka.common.message.OffsetFetchResponseData;
import io.kroxylicious.kafka.common.message.RequestHeaderData;
import io.kroxylicious.kafka.common.message.ResponseHeaderData;
import io.kroxylicious.testing.filter.assertj.MockFilterContextAssert;
import io.kroxylicious.testing.filter.context.MockFilterContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class TopicPrefixerFilterTest {

    private static final String PREFIX = "p_";
    private static final short METADATA_VERSION = 12;
    private static final short FETCH_VERSION = 15;
    private static final short DESCRIBE_CONFIGS_VERSION = 4;
    private static final short FIND_COORDINATOR_VERSION = 4;
    private static final short OFFSET_FETCH_VERSION = 7;
    private static final short LIST_GROUPS_VERSION = 4;
    private static final short JOIN_GROUP_VERSION = 9;
    private static final byte COORDINATOR_TYPE_GROUP = 0;
    private static final byte COORDINATOR_TYPE_TRANSACTION = 1;

    private TopicPrefixerFilter filter;

    @BeforeEach
    void beforeEach() {
        // Same prefix for both, matching this test class's pre-existing behaviour; independent
        // topic/group renaming is covered separately by TopicPrefixerIT.
        filter = new TopicPrefixerFilter(new PrefixRenamer(PREFIX), new PrefixRenamer(PREFIX));
    }

    @Test
    void addsPrefixToOrdinaryTopicInMetadataResponse() {
        var header = new ResponseHeaderData();
        var response = new MetadataResponseData();
        var topic = new MetadataResponseData.MetadataResponseTopic();
        topic.setName("foo");
        response.setTopics(new MetadataResponseData.MetadataResponseTopicCollection(List.of(topic).iterator()));
        var context = MockFilterContext.builder(header, response).build();

        var stage = filter.onMetadataResponse(METADATA_VERSION, header, response, context);

        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardResponse()
                .hasMessageInstanceOfSatisfying(MetadataResponseData.class,
                        forwarded -> assertThat(forwarded.topics().iterator().next().name()).isEqualTo("p_foo")));
    }

    @Test
    void leavesInternalTopicUnprefixedInMetadataResponse() {
        var header = new ResponseHeaderData();
        var response = new MetadataResponseData();
        var topic = new MetadataResponseData.MetadataResponseTopic();
        topic.setName("_schemas");
        response.setTopics(new MetadataResponseData.MetadataResponseTopicCollection(List.of(topic).iterator()));
        var context = MockFilterContext.builder(header, response).build();

        var stage = filter.onMetadataResponse(METADATA_VERSION, header, response, context);

        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardResponse()
                .hasMessageInstanceOfSatisfying(MetadataResponseData.class,
                        forwarded -> assertThat(forwarded.topics().iterator().next().name()).isEqualTo("_schemas")));
    }

    @Test
    void stripsPrefixFromNamedTopicInMetadataRequest() {
        var header = new RequestHeaderData();
        var request = new MetadataRequestData();
        var topic = new MetadataRequestData.MetadataRequestTopic();
        topic.setName("p_foo");
        request.setTopics(List.of(topic));
        var context = MockFilterContext.builder(header, request).build();

        var stage = filter.onMetadataRequest(METADATA_VERSION, header, request, context);

        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardRequest()
                .hasMessageInstanceOfSatisfying(MetadataRequestData.class,
                        forwarded -> assertThat(forwarded.topics().iterator().next().name()).isEqualTo("foo")));
    }

    @Test
    void leavesWildcardMetadataRequestUntouched() {
        var header = new RequestHeaderData();
        var request = new MetadataRequestData();
        request.setTopics(null);
        var context = MockFilterContext.builder(header, request).build();

        var stage = filter.onMetadataRequest(METADATA_VERSION, header, request, context);

        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardRequest()
                .hasMessageInstanceOfSatisfying(MetadataRequestData.class, forwarded -> assertThat(forwarded.topics()).isNull()));
    }

    @Test
    void stripsPrefixFromFetchRequestTopic() {
        var header = new RequestHeaderData();
        var request = new FetchRequestData();
        var topic = new FetchRequestData.FetchTopic();
        topic.setTopic("p_foo");
        request.setTopics(List.of(topic));
        var context = MockFilterContext.builder(header, request).build();

        var stage = filter.onFetchRequest(FETCH_VERSION, header, request, context);

        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardRequest()
                .hasMessageInstanceOfSatisfying(FetchRequestData.class,
                        forwarded -> assertThat(forwarded.topics().get(0).topic()).isEqualTo("foo")));
    }

    @Test
    void addsPrefixToFetchResponseTopic() {
        var header = new ResponseHeaderData();
        var response = new FetchResponseData();
        var topic = new FetchResponseData.FetchableTopicResponse();
        topic.setTopic("foo");
        response.setResponses(List.of(topic));
        var context = MockFilterContext.builder(header, response).build();

        var stage = filter.onFetchResponse(FETCH_VERSION, header, response, context);

        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardResponse()
                .hasMessageInstanceOfSatisfying(FetchResponseData.class,
                        forwarded -> assertThat(forwarded.responses().get(0).topic()).isEqualTo("p_foo")));
    }

    @Test
    void stripsPrefixFromDescribeConfigsTopicResource() {
        var header = new RequestHeaderData();
        var request = new DescribeConfigsRequestData();
        var resource = new DescribeConfigsRequestData.DescribeConfigsResource();
        resource.setResourceType((byte) 2);
        resource.setResourceName("p_foo");
        request.setResources(List.of(resource));
        var context = MockFilterContext.builder(header, request).build();

        var stage = filter.onDescribeConfigsRequest(DESCRIBE_CONFIGS_VERSION, header, request, context);

        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardRequest()
                .hasMessageInstanceOfSatisfying(DescribeConfigsRequestData.class,
                        forwarded -> assertThat(forwarded.resources().get(0).resourceName()).isEqualTo("foo")));
    }

    @Test
    void leavesNonTopicResourceUntouchedInDescribeConfigsRequest() {
        var header = new RequestHeaderData();
        var request = new DescribeConfigsRequestData();
        var resource = new DescribeConfigsRequestData.DescribeConfigsResource();
        resource.setResourceType((byte) 4); // BROKER, not TOPIC
        resource.setResourceName("0");
        request.setResources(List.of(resource));
        var context = MockFilterContext.builder(header, request).build();

        var stage = filter.onDescribeConfigsRequest(DESCRIBE_CONFIGS_VERSION, header, request, context);

        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardRequest()
                .hasMessageInstanceOfSatisfying(DescribeConfigsRequestData.class,
                        forwarded -> assertThat(forwarded.resources().get(0).resourceName()).isEqualTo("0")));
    }

    @Test
    void addsPrefixToDescribeConfigsTopicResult() {
        var header = new ResponseHeaderData();
        var response = new DescribeConfigsResponseData();
        var result = new DescribeConfigsResponseData.DescribeConfigsResult();
        result.setResourceType((byte) 2);
        result.setResourceName("foo");
        response.setResults(List.of(result));
        var context = MockFilterContext.builder(header, response).build();

        var stage = filter.onDescribeConfigsResponse(DESCRIBE_CONFIGS_VERSION, header, response, context);

        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(r -> MockFilterContextAssert.assertThat(r)
                .isForwardResponse()
                .hasMessageInstanceOfSatisfying(DescribeConfigsResponseData.class,
                        forwarded -> assertThat(forwarded.results().get(0).resourceName()).isEqualTo("p_foo")));
    }

    @Test
    void stripsGroupIdAndTopicNameFromOffsetFetchRequest() {
        var header = new RequestHeaderData();
        var request = new OffsetFetchRequestData();
        request.setGroupId("p_my-group");
        var topic = new OffsetFetchRequestData.OffsetFetchRequestTopic();
        topic.setName("p_foo");
        request.setTopics(List.of(topic));
        var context = MockFilterContext.builder(header, request).build();

        var stage = filter.onOffsetFetchRequest(OFFSET_FETCH_VERSION, header, request, context);

        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardRequest()
                .hasMessageInstanceOfSatisfying(OffsetFetchRequestData.class, forwarded -> {
                    assertThat(forwarded.groupId()).isEqualTo("my-group");
                    assertThat(forwarded.topics().get(0).name()).isEqualTo("foo");
                }));
    }

    @Test
    void addsPrefixToGroupIdAndTopicNameInOffsetFetchResponse() {
        var header = new ResponseHeaderData();
        var response = new OffsetFetchResponseData();
        var topic = new OffsetFetchResponseData.OffsetFetchResponseTopic();
        topic.setName("foo");
        response.setTopics(List.of(topic));
        var group = new OffsetFetchResponseData.OffsetFetchResponseGroup();
        group.setGroupId("my-group");
        var groupTopic = new OffsetFetchResponseData.OffsetFetchResponseTopics();
        groupTopic.setName("foo");
        group.setTopics(List.of(groupTopic));
        response.setGroups(List.of(group));
        var context = MockFilterContext.builder(header, response).build();

        var stage = filter.onOffsetFetchResponse(OFFSET_FETCH_VERSION, header, response, context);

        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardResponse()
                .hasMessageInstanceOfSatisfying(OffsetFetchResponseData.class, forwarded -> {
                    assertThat(forwarded.topics().get(0).name()).isEqualTo("p_foo");
                    assertThat(forwarded.groups().get(0).groupId()).isEqualTo("p_my-group");
                    assertThat(forwarded.groups().get(0).topics().get(0).name()).isEqualTo("p_foo");
                }));
    }

    @Test
    void addsPrefixToGroupIdInListGroupsResponse() {
        var header = new ResponseHeaderData();
        var response = new ListGroupsResponseData();
        var group = new ListGroupsResponseData.ListedGroup();
        group.setGroupId("my-group");
        response.setGroups(List.of(group));
        var context = MockFilterContext.builder(header, response).build();

        var stage = filter.onListGroupsResponse(LIST_GROUPS_VERSION, header, response, context);

        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardResponse()
                .hasMessageInstanceOfSatisfying(ListGroupsResponseData.class,
                        forwarded -> assertThat(forwarded.groups().get(0).groupId()).isEqualTo("p_my-group")));
    }

    @Test
    void stripsGroupIdFromJoinGroupRequest() {
        var header = new RequestHeaderData();
        var request = new JoinGroupRequestData();
        request.setGroupId("p_my-group");
        var context = MockFilterContext.builder(header, request).build();

        var stage = filter.onJoinGroupRequest(JOIN_GROUP_VERSION, header, request, context);

        assertThat(stage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardRequest()
                .hasMessageInstanceOfSatisfying(JoinGroupRequestData.class,
                        forwarded -> assertThat(forwarded.groupId()).isEqualTo("my-group")));
    }

    @Test
    void findCoordinatorRoundTripRenamesGroupLookup() {
        var reqHeader = new RequestHeaderData();
        reqHeader.setCorrelationId(42);
        var request = new FindCoordinatorRequestData();
        request.setKeyType(COORDINATOR_TYPE_GROUP);
        request.setCoordinatorKeys(List.of("p_my-group"));
        var reqContext = MockFilterContext.builder(reqHeader, request).build();

        var reqStage = filter.onFindCoordinatorRequest(FIND_COORDINATOR_VERSION, reqHeader, request, reqContext);
        assertThat(reqStage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardRequest()
                .hasMessageInstanceOfSatisfying(FindCoordinatorRequestData.class,
                        forwarded -> assertThat(forwarded.coordinatorKeys()).containsExactly("my-group")));

        var respHeader = new ResponseHeaderData();
        respHeader.setCorrelationId(42);
        var response = new FindCoordinatorResponseData();
        var coordinator = new FindCoordinatorResponseData.Coordinator();
        coordinator.setKey("my-group");
        response.setCoordinators(List.of(coordinator));
        var respContext = MockFilterContext.builder(respHeader, response).build();

        var respStage = filter.onFindCoordinatorResponse(FIND_COORDINATOR_VERSION, respHeader, response, respContext);
        assertThat(respStage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardResponse()
                .hasMessageInstanceOfSatisfying(FindCoordinatorResponseData.class,
                        forwarded -> assertThat(forwarded.coordinators().get(0).key()).isEqualTo("p_my-group")));
    }

    @Test
    void findCoordinatorLeavesTransactionLookupUntouched() {
        var reqHeader = new RequestHeaderData();
        reqHeader.setCorrelationId(43);
        var request = new FindCoordinatorRequestData();
        request.setKeyType(COORDINATOR_TYPE_TRANSACTION);
        request.setCoordinatorKeys(List.of("my-txn-id"));
        var reqContext = MockFilterContext.builder(reqHeader, request).build();

        var reqStage = filter.onFindCoordinatorRequest(FIND_COORDINATOR_VERSION, reqHeader, request, reqContext);
        assertThat(reqStage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardRequest()
                .hasMessageInstanceOfSatisfying(FindCoordinatorRequestData.class,
                        forwarded -> assertThat(forwarded.coordinatorKeys()).containsExactly("my-txn-id")));

        var respHeader = new ResponseHeaderData();
        respHeader.setCorrelationId(43);
        var response = new FindCoordinatorResponseData();
        var coordinator = new FindCoordinatorResponseData.Coordinator();
        coordinator.setKey("my-txn-id");
        response.setCoordinators(List.of(coordinator));
        var respContext = MockFilterContext.builder(respHeader, response).build();

        // Not preceded by a *group* lookup with this correlation id, so the response must be left alone.
        var respStage = filter.onFindCoordinatorResponse(FIND_COORDINATOR_VERSION, respHeader, response, respContext);
        assertThat(respStage).succeedsWithin(Duration.ZERO).satisfies(result -> MockFilterContextAssert.assertThat(result)
                .isForwardResponse()
                .hasMessageInstanceOfSatisfying(FindCoordinatorResponseData.class,
                        forwarded -> assertThat(forwarded.coordinators().get(0).key()).isEqualTo("my-txn-id")));
    }
}
