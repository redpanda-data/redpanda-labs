package demo.topicprefixer;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Configuration for the {@link TopicPrefixer} filter: independent {@link RenamingConfig}s for
 * topics and for consumer groups, e.g.
 * <pre>{@code
 * config:
 *   topics:
 *     prefix: "p_"
 *   groups:
 *     prefix: "g_"
 * }</pre>
 */
public class TopicPrefixerConfig {

    private final RenamingConfig topics;
    private final RenamingConfig groups;

    public TopicPrefixerConfig(@JsonProperty(value = "topics", required = true) RenamingConfig topics,
                                @JsonProperty(value = "groups", required = true) RenamingConfig groups) {
        this.topics = topics;
        this.groups = groups;
    }

    public RenamingConfig topics() {
        return topics;
    }

    public RenamingConfig groups() {
        return groups;
    }
}
