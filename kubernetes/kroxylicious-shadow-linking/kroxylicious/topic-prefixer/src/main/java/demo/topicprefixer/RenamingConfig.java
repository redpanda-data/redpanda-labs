package demo.topicprefixer;

import java.util.Map;

import com.fasterxml.jackson.annotation.JsonProperty;

import io.kroxylicious.proxy.plugin.PluginConfigurationException;

/**
 * Configures how one kind of name - topics, or consumer groups - is renamed as it crosses the
 * proxy. Exactly one of {@code prefix} or {@code mapping} must be given:
 * <pre>{@code
 * topics:
 *   prefix: "p_"
 * groups:
 *   mapping:
 *     my-group: renamed-group
 * }</pre>
 * {@code prefix} adds/strips a fixed string (see {@link PrefixRenamer}); {@code mapping} renames
 * via an explicit before -&gt; after table (see {@link MappingRenamer}), leaving any name that isn't
 * in the table untouched.
 */
public class RenamingConfig {

    private final String prefix;
    private final Map<String, String> mapping;

    public RenamingConfig(@JsonProperty("prefix") String prefix, @JsonProperty("mapping") Map<String, String> mapping) {
        this.prefix = prefix;
        this.mapping = mapping;
    }

    public String prefix() {
        return prefix;
    }

    public Map<String, String> mapping() {
        return mapping;
    }

    /**
     * @param which used only to make a misconfiguration's error message point at the right place
     *              ({@code "topics"} or {@code "groups"})
     */
    NameRenamer toRenamer(String which) {
        boolean hasPrefix = prefix != null;
        boolean hasMapping = mapping != null;
        if (hasPrefix == hasMapping) {
            throw new PluginConfigurationException(
                    "exactly one of 'prefix' or 'mapping' must be specified for '%s'".formatted(which));
        }
        return hasPrefix ? new PrefixRenamer(prefix) : new MappingRenamer(mapping);
    }
}
