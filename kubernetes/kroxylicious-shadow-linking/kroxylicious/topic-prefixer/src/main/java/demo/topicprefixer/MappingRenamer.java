package demo.topicprefixer;

import java.util.HashMap;
import java.util.Map;

import io.kroxylicious.proxy.plugin.PluginConfigurationException;

/**
 * Renames names via an explicit before -&gt; after mapping, rather than a fixed prefix. A name that
 * isn't one of the configured keys (real -&gt; presented direction) or values (presented -&gt; real
 * direction) passes through completely unchanged - this filter never hides a name, it only ever
 * renames the ones you've told it to.
 * <p>
 * The mapping must be invertible: two different real names can't map to the same presented name,
 * since that would make the reverse (presented -&gt; real) direction ambiguous. This is checked
 * eagerly, at filter start-up, rather than discovered later against live traffic.
 */
final class MappingRenamer implements NameRenamer {

    private final Map<String, String> forward;
    private final Map<String, String> reverse;

    MappingRenamer(Map<String, String> mapping) {
        this.forward = Map.copyOf(mapping);
        var reversed = new HashMap<String, String>();
        mapping.forEach((real, presented) -> {
            String clash = reversed.put(presented, real);
            if (clash != null) {
                throw new PluginConfigurationException(
                        "mapping is not invertible: both '%s' and '%s' are mapped to '%s'".formatted(clash, real, presented));
            }
        });
        this.reverse = Map.copyOf(reversed);
    }

    @Override
    public String rename(String realName) {
        return forward.getOrDefault(realName, realName);
    }

    @Override
    public String unrename(String presentedName) {
        return reverse.getOrDefault(presentedName, presentedName);
    }
}
