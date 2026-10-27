package demo.topicprefixer;

import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.CompletionStage;

import io.kroxylicious.kafka.common.message.ApiVersionsResponseData;
import io.kroxylicious.kafka.common.message.ConsumerGroupDescribeRequestData;
import io.kroxylicious.kafka.common.message.ConsumerGroupDescribeResponseData;
import io.kroxylicious.kafka.common.message.DescribeConfigsRequestData;
import io.kroxylicious.kafka.common.message.DescribeConfigsResponseData;
import io.kroxylicious.kafka.common.message.DescribeGroupsRequestData;
import io.kroxylicious.kafka.common.message.DescribeGroupsResponseData;
import io.kroxylicious.kafka.common.message.FetchRequestData;
import io.kroxylicious.kafka.common.message.FetchResponseData;
import io.kroxylicious.kafka.common.message.FindCoordinatorRequestData;
import io.kroxylicious.kafka.common.message.FindCoordinatorResponseData;
import io.kroxylicious.kafka.common.message.HeartbeatRequestData;
import io.kroxylicious.kafka.common.message.JoinGroupRequestData;
import io.kroxylicious.kafka.common.message.LeaveGroupRequestData;
import io.kroxylicious.kafka.common.message.ListGroupsResponseData;
import io.kroxylicious.kafka.common.message.ListOffsetsRequestData;
import io.kroxylicious.kafka.common.message.ListOffsetsResponseData;
import io.kroxylicious.kafka.common.message.MetadataRequestData;
import io.kroxylicious.kafka.common.message.MetadataResponseData;
import io.kroxylicious.kafka.common.message.OffsetCommitRequestData;
import io.kroxylicious.kafka.common.message.OffsetCommitResponseData;
import io.kroxylicious.kafka.common.message.OffsetDeleteRequestData;
import io.kroxylicious.kafka.common.message.OffsetDeleteResponseData;
import io.kroxylicious.kafka.common.message.OffsetFetchRequestData;
import io.kroxylicious.kafka.common.message.OffsetFetchResponseData;
import io.kroxylicious.kafka.common.message.RequestHeaderData;
import io.kroxylicious.kafka.common.message.ResponseHeaderData;
import io.kroxylicious.kafka.common.message.SyncGroupRequestData;
import io.kroxylicious.kafka.common.protocol.ApiKeys;
import io.kroxylicious.kafka.transform.ApiVersionsResponseTransformer;
import io.kroxylicious.proxy.filter.ApiVersionsResponseFilter;
import io.kroxylicious.proxy.filter.ConsumerGroupDescribeRequestFilter;
import io.kroxylicious.proxy.filter.ConsumerGroupDescribeResponseFilter;
import io.kroxylicious.proxy.filter.DescribeConfigsRequestFilter;
import io.kroxylicious.proxy.filter.DescribeConfigsResponseFilter;
import io.kroxylicious.proxy.filter.DescribeGroupsRequestFilter;
import io.kroxylicious.proxy.filter.DescribeGroupsResponseFilter;
import io.kroxylicious.proxy.filter.FetchRequestFilter;
import io.kroxylicious.proxy.filter.FetchResponseFilter;
import io.kroxylicious.proxy.filter.FilterContext;
import io.kroxylicious.proxy.filter.FindCoordinatorRequestFilter;
import io.kroxylicious.proxy.filter.FindCoordinatorResponseFilter;
import io.kroxylicious.proxy.filter.HeartbeatRequestFilter;
import io.kroxylicious.proxy.filter.JoinGroupRequestFilter;
import io.kroxylicious.proxy.filter.LeaveGroupRequestFilter;
import io.kroxylicious.proxy.filter.ListGroupsResponseFilter;
import io.kroxylicious.proxy.filter.ListOffsetsRequestFilter;
import io.kroxylicious.proxy.filter.ListOffsetsResponseFilter;
import io.kroxylicious.proxy.filter.MetadataRequestFilter;
import io.kroxylicious.proxy.filter.MetadataResponseFilter;
import io.kroxylicious.proxy.filter.OffsetCommitRequestFilter;
import io.kroxylicious.proxy.filter.OffsetCommitResponseFilter;
import io.kroxylicious.proxy.filter.OffsetDeleteRequestFilter;
import io.kroxylicious.proxy.filter.OffsetDeleteResponseFilter;
import io.kroxylicious.proxy.filter.OffsetFetchRequestFilter;
import io.kroxylicious.proxy.filter.OffsetFetchResponseFilter;
import io.kroxylicious.proxy.filter.RequestFilterResult;
import io.kroxylicious.proxy.filter.ResponseFilterResult;
import io.kroxylicious.proxy.filter.SyncGroupRequestFilter;

import static io.kroxylicious.kafka.transform.ApiVersionsResponseTransformers.removeApiKeys;

/**
 * Presents every topic and consumer group on the backing cluster to clients of the virtual cluster
 * under a cosmetic rename, without ever renaming the real topic/group. Topics and consumer groups
 * are renamed independently, by two separate {@link NameRenamer}s - see {@link TopicPrefixer} for
 * the overall rationale and {@link RenamingConfig} for how each renamer is configured (a fixed
 * prefix, or an explicit before/after mapping).
 * <p>
 * Covers the RPCs needed to discover and replicate both topics and consumer group offset commits:
 * {@code Metadata} (topic discovery), {@code DescribeConfigs} (reading a topic's configuration
 * before creating the corresponding shadow topic), {@code ListOffsets} and {@code Fetch} (pulling
 * records); and, for consumer groups, {@code FindCoordinator}, {@code ListGroups},
 * {@code DescribeGroups}, {@code ConsumerGroupDescribe}, {@code JoinGroup}, {@code SyncGroup},
 * {@code Heartbeat}, {@code LeaveGroup}, {@code OffsetFetch}, {@code OffsetCommit} and
 * {@code OffsetDelete} - topic names embedded in offset commits go through the same topic renamer
 * as the data-plane RPCs above, so a shadowed commit always points at the same-named shadowed
 * topic, regardless of how topics and groups are each configured to be renamed.
 * <p>
 * This is demo-quality code, not a general-purpose substitute for the {@code MultiTenant} filter -
 * extend it if your own testing finds gaps. Notably out of scope: producing through the proxy
 * (would need {@code CreateTopicsRequestFilter}/{@code ProduceRequestFilter} and response
 * counterparts) and the transactional producer lifecycle ({@code InitProducerId},
 * {@code AddOffsetsToTxn}, {@code AddPartitionsToTxn}, {@code TxnOffsetCommit}, {@code EndTxn}) -
 * {@code FindCoordinator} lookups for a transaction id (as opposed to a group id) are deliberately
 * left untouched, see {@link #onFindCoordinatorRequest}. The newer KIP-848
 * {@code ConsumerGroupHeartbeat}-based group protocol also isn't covered, matching a gap in
 * Kroxylicious's own {@code MultiTenant} filter.
 */
class TopicPrefixerFilter implements
        ApiVersionsResponseFilter,
        MetadataRequestFilter, MetadataResponseFilter,
        DescribeConfigsRequestFilter, DescribeConfigsResponseFilter,
        ListOffsetsRequestFilter, ListOffsetsResponseFilter,
        FetchRequestFilter, FetchResponseFilter,
        FindCoordinatorRequestFilter, FindCoordinatorResponseFilter,
        ListGroupsResponseFilter,
        DescribeGroupsRequestFilter, DescribeGroupsResponseFilter,
        ConsumerGroupDescribeRequestFilter, ConsumerGroupDescribeResponseFilter,
        JoinGroupRequestFilter,
        SyncGroupRequestFilter,
        HeartbeatRequestFilter,
        LeaveGroupRequestFilter,
        OffsetFetchRequestFilter, OffsetFetchResponseFilter,
        OffsetCommitRequestFilter, OffsetCommitResponseFilter,
        OffsetDeleteRequestFilter, OffsetDeleteResponseFilter {

    private static final ApiVersionsResponseTransformer API_VERSIONS_RESPONSE_INTERCEPTOR = removeApiKeys(Set.of(ApiKeys.DESCRIBE_TOPIC_PARTITIONS));

    /** Kafka protocol {@code ConfigResource.Type} for a topic resource (as opposed to e.g. a broker). */
    private static final byte RESOURCE_TYPE_TOPIC = 2;

    /** Kafka protocol {@code FindCoordinatorRequest.CoordinatorType} for a consumer group (as opposed to a transaction id). */
    private static final byte COORDINATOR_TYPE_GROUP = 0;

    private final NameRenamer topics;
    private final NameRenamer groups;

    /**
     * {@code FindCoordinator} responses don't restate whether the lookup was for a group or a
     * transaction id, so this tracks the correlation ids of in-flight *group* lookups (the only
     * ones this filter rewrites) between {@link #onFindCoordinatorRequest} and
     * {@link #onFindCoordinatorResponse}. Filter instances are scoped to a single connection and
     * its messages are processed sequentially, so a plain (unsynchronized) mutable set is fine here
     * - same assumption {@code MultiTenantFilter} makes with its own cached tenant prefix field.
     */
    private final Set<Integer> pendingGroupCoordinatorLookups = new HashSet<>();

    TopicPrefixerFilter(NameRenamer topics, NameRenamer groups) {
        this.topics = topics;
        this.groups = groups;
    }

    @Override
    public CompletionStage<ResponseFilterResult> onApiVersionsResponse(short apiVersion, ResponseHeaderData header, ApiVersionsResponseData response,
                                                                         FilterContext context) {
        return context.forwardResponse(header, API_VERSIONS_RESPONSE_INTERCEPTOR.transform(response));
    }

    // ---- topic metadata / data plane ----

    @Override
    public CompletionStage<RequestFilterResult> onMetadataRequest(short apiVersion, RequestHeaderData header, MetadataRequestData request,
                                                                    FilterContext context) {
        if (request.topics() != null) {
            // request.topics() == null means "give me all the topics" - nothing to rewrite here.
            request.topics().forEach(topic -> topic.setName(topics.unrename(topic.name())));
        }
        return context.forwardRequest(header, request);
    }

    @Override
    public CompletionStage<ResponseFilterResult> onMetadataResponse(short apiVersion, ResponseHeaderData header, MetadataResponseData response,
                                                                      FilterContext context) {
        response.topics().forEach(topic -> topic.setName(topics.rename(topic.name())));
        return context.forwardResponse(header, response);
    }

    @Override
    public CompletionStage<RequestFilterResult> onListOffsetsRequest(short apiVersion, RequestHeaderData header, ListOffsetsRequestData request,
                                                                       FilterContext context) {
        request.topics().forEach(topic -> topic.setName(topics.unrename(topic.name())));
        return context.forwardRequest(header, request);
    }

    @Override
    public CompletionStage<ResponseFilterResult> onListOffsetsResponse(short apiVersion, ResponseHeaderData header, ListOffsetsResponseData response,
                                                                        FilterContext context) {
        response.topics().forEach(topic -> topic.setName(topics.rename(topic.name())));
        return context.forwardResponse(header, response);
    }

    @Override
    public CompletionStage<RequestFilterResult> onDescribeConfigsRequest(short apiVersion, RequestHeaderData header, DescribeConfigsRequestData request,
                                                                          FilterContext context) {
        request.resources().stream()
                .filter(resource -> resource.resourceType() == RESOURCE_TYPE_TOPIC)
                .forEach(resource -> resource.setResourceName(topics.unrename(resource.resourceName())));
        return context.forwardRequest(header, request);
    }

    @Override
    public CompletionStage<ResponseFilterResult> onDescribeConfigsResponse(short apiVersion, ResponseHeaderData header, DescribeConfigsResponseData response,
                                                                            FilterContext context) {
        response.results().stream()
                .filter(result -> result.resourceType() == RESOURCE_TYPE_TOPIC)
                .forEach(result -> result.setResourceName(topics.rename(result.resourceName())));
        return context.forwardResponse(header, response);
    }

    @Override
    public CompletionStage<RequestFilterResult> onFetchRequest(short apiVersion, RequestHeaderData header, FetchRequestData request, FilterContext context) {
        request.topics().forEach(topic -> topic.setTopic(topics.unrename(topic.topic())));
        return context.forwardRequest(header, request);
    }

    @Override
    public CompletionStage<ResponseFilterResult> onFetchResponse(short apiVersion, ResponseHeaderData header, FetchResponseData response, FilterContext context) {
        response.responses().forEach(topic -> topic.setTopic(topics.rename(topic.topic())));
        return context.forwardResponse(header, response);
    }

    // ---- consumer group discovery ----

    /**
     * Rewrites {@code FindCoordinator} lookups for a consumer group id. Lookups for a transaction
     * id ({@code keyType == 1}) are left completely untouched, since this filter doesn't implement
     * the transactional producer lifecycle needed to keep a renamed transaction id consistent.
     */
    @Override
    public CompletionStage<RequestFilterResult> onFindCoordinatorRequest(short apiVersion, RequestHeaderData header, FindCoordinatorRequestData request,
                                                                          FilterContext context) {
        if (request.keyType() == COORDINATOR_TYPE_GROUP) {
            pendingGroupCoordinatorLookups.add(header.correlationId());
            // the singular `key` field was used up to and including version 3
            if (request.key() != null && !request.key().isEmpty()) {
                request.setKey(groups.unrename(request.key()));
            }
            request.setCoordinatorKeys(request.coordinatorKeys().stream().map(groups::unrename).toList());
        }
        return context.forwardRequest(header, request);
    }

    @Override
    public CompletionStage<ResponseFilterResult> onFindCoordinatorResponse(short apiVersion, ResponseHeaderData header, FindCoordinatorResponseData response,
                                                                            FilterContext context) {
        if (pendingGroupCoordinatorLookups.remove(header.correlationId())) {
            response.coordinators().forEach(coordinator -> coordinator.setKey(groups.rename(coordinator.key())));
        }
        return context.forwardResponse(header, response);
    }

    @Override
    public CompletionStage<ResponseFilterResult> onListGroupsResponse(short apiVersion, ResponseHeaderData header, ListGroupsResponseData response,
                                                                       FilterContext context) {
        response.groups().forEach(group -> group.setGroupId(groups.rename(group.groupId())));
        return context.forwardResponse(header, response);
    }

    @Override
    public CompletionStage<RequestFilterResult> onDescribeGroupsRequest(short apiVersion, RequestHeaderData header, DescribeGroupsRequestData request,
                                                                         FilterContext context) {
        request.setGroups(request.groups().stream().map(groups::unrename).toList());
        return context.forwardRequest(header, request);
    }

    @Override
    public CompletionStage<ResponseFilterResult> onDescribeGroupsResponse(short apiVersion, ResponseHeaderData header, DescribeGroupsResponseData response,
                                                                           FilterContext context) {
        response.groups().forEach(group -> group.setGroupId(groups.rename(group.groupId())));
        return context.forwardResponse(header, response);
    }

    @Override
    public CompletionStage<RequestFilterResult> onConsumerGroupDescribeRequest(short apiVersion, RequestHeaderData header, ConsumerGroupDescribeRequestData request,
                                                                                 FilterContext context) {
        request.setGroupIds(request.groupIds().stream().map(groups::unrename).toList());
        return context.forwardRequest(header, request);
    }

    @Override
    public CompletionStage<ResponseFilterResult> onConsumerGroupDescribeResponse(short apiVersion, ResponseHeaderData header,
                                                                                  ConsumerGroupDescribeResponseData response, FilterContext context) {
        response.groups().forEach(group -> group.setGroupId(groups.rename(group.groupId())));
        return context.forwardResponse(header, response);
    }

    // ---- consumer group membership ----
    // These only carry the group id on the request; the response never echoes it back.

    @Override
    public CompletionStage<RequestFilterResult> onJoinGroupRequest(short apiVersion, RequestHeaderData header, JoinGroupRequestData request,
                                                                     FilterContext context) {
        request.setGroupId(groups.unrename(request.groupId()));
        return context.forwardRequest(header, request);
    }

    @Override
    public CompletionStage<RequestFilterResult> onSyncGroupRequest(short apiVersion, RequestHeaderData header, SyncGroupRequestData request,
                                                                     FilterContext context) {
        request.setGroupId(groups.unrename(request.groupId()));
        return context.forwardRequest(header, request);
    }

    @Override
    public CompletionStage<RequestFilterResult> onHeartbeatRequest(short apiVersion, RequestHeaderData header, HeartbeatRequestData request,
                                                                     FilterContext context) {
        request.setGroupId(groups.unrename(request.groupId()));
        return context.forwardRequest(header, request);
    }

    @Override
    public CompletionStage<RequestFilterResult> onLeaveGroupRequest(short apiVersion, RequestHeaderData header, LeaveGroupRequestData request,
                                                                     FilterContext context) {
        request.setGroupId(groups.unrename(request.groupId()));
        return context.forwardRequest(header, request);
    }

    // ---- consumer group offsets (commits) ----
    // Topic names here go through the same `topics` renamer as the data-plane RPCs above, so a
    // commit always points at the same-named shadowed topic.

    @Override
    public CompletionStage<RequestFilterResult> onOffsetFetchRequest(short apiVersion, RequestHeaderData header, OffsetFetchRequestData request,
                                                                      FilterContext context) {
        // the singular groupId/topics fields were used up to and including version 7
        if (request.groupId() != null && !request.groupId().isEmpty()) {
            request.setGroupId(groups.unrename(request.groupId()));
        }
        if (request.topics() != null) {
            request.topics().forEach(topic -> topic.setName(topics.unrename(topic.name())));
        }
        request.groups().forEach(requestGroup -> {
            requestGroup.setGroupId(groups.unrename(requestGroup.groupId()));
            if (requestGroup.topics() != null) {
                requestGroup.topics().forEach(topic -> topic.setName(topics.unrename(topic.name())));
            }
        });
        return context.forwardRequest(header, request);
    }

    @Override
    public CompletionStage<ResponseFilterResult> onOffsetFetchResponse(short apiVersion, ResponseHeaderData header, OffsetFetchResponseData response,
                                                                        FilterContext context) {
        response.topics().forEach(topic -> topic.setName(topics.rename(topic.name())));
        response.groups().forEach(responseGroup -> {
            responseGroup.setGroupId(groups.rename(responseGroup.groupId()));
            responseGroup.topics().forEach(topic -> topic.setName(topics.rename(topic.name())));
        });
        return context.forwardResponse(header, response);
    }

    @Override
    public CompletionStage<RequestFilterResult> onOffsetCommitRequest(short apiVersion, RequestHeaderData header, OffsetCommitRequestData request,
                                                                       FilterContext context) {
        request.setGroupId(groups.unrename(request.groupId()));
        request.topics().forEach(topic -> topic.setName(topics.unrename(topic.name())));
        return context.forwardRequest(header, request);
    }

    @Override
    public CompletionStage<ResponseFilterResult> onOffsetCommitResponse(short apiVersion, ResponseHeaderData header, OffsetCommitResponseData response,
                                                                         FilterContext context) {
        response.topics().forEach(topic -> topic.setName(topics.rename(topic.name())));
        return context.forwardResponse(header, response);
    }

    @Override
    public CompletionStage<RequestFilterResult> onOffsetDeleteRequest(short apiVersion, RequestHeaderData header, OffsetDeleteRequestData request,
                                                                       FilterContext context) {
        request.setGroupId(groups.unrename(request.groupId()));
        request.topics().forEach(topic -> topic.setName(topics.unrename(topic.name())));
        return context.forwardRequest(header, request);
    }

    @Override
    public CompletionStage<ResponseFilterResult> onOffsetDeleteResponse(short apiVersion, ResponseHeaderData header, OffsetDeleteResponseData response,
                                                                         FilterContext context) {
        response.topics().forEach(topic -> topic.setName(topics.rename(topic.name())));
        return context.forwardResponse(header, response);
    }
}
