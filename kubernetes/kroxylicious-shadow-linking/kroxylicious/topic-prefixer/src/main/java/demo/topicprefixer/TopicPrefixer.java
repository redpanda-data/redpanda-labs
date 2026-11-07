package demo.topicprefixer;

import io.kroxylicious.proxy.filter.FilterFactory;
import io.kroxylicious.proxy.filter.FilterFactoryContext;
import io.kroxylicious.proxy.plugin.Plugin;
import io.kroxylicious.proxy.plugin.PluginConfigurationException;
import io.kroxylicious.proxy.plugin.Plugins;

/**
 * Filter factory for {@link TopicPrefixerFilter}.
 * <p>
 * This is a one-way, demo-only counterpart to Kroxylicious's built-in {@code MultiTenant} filter.
 * {@code MultiTenant} adds a prefix on the way IN (client -&gt; backend) and strips it on the way OUT
 * (backend -&gt; client), so any client of the virtual cluster only ever sees the unprefixed name -
 * the prefix is purely an implementation detail of how the backend cluster stores the data.
 * <p>
 * This filter does the opposite: it renames on the way OUT (backend -&gt; client) and un-renames on
 * the way IN (client -&gt; backend), so the rename is entirely cosmetic and is visible to every
 * client of the virtual cluster - including Redpanda's Shadow Link, which is the point of this demo.
 * The real topic/group on the backing cluster is never renamed. Topics and consumer groups are
 * renamed independently - see {@link TopicPrefixerConfig} and {@link RenamingConfig}.
 */
@Plugin(configType = TopicPrefixerConfig.class)
public class TopicPrefixer implements FilterFactory<TopicPrefixerConfig, TopicPrefixer.Renamers> {

    /** The resolved, ready-to-use renamers handed from {@link #initialize} to {@link #createFilter}. */
    record Renamers(NameRenamer topics, NameRenamer groups) {}

    @Override
    public Renamers initialize(FilterFactoryContext context, TopicPrefixerConfig config) throws PluginConfigurationException {
        Plugins.requireConfig(this, config);
        return new Renamers(config.topics().toRenamer("topics"), config.groups().toRenamer("groups"));
    }

    @Override
    public TopicPrefixerFilter createFilter(FilterFactoryContext context, Renamers renamers) {
        return new TopicPrefixerFilter(renamers.topics(), renamers.groups());
    }
}
