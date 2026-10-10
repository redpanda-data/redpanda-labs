package demo.topicprefixer;

import java.util.Map;

import io.kroxylicious.proxy.plugin.PluginConfigurationException;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class RenamingConfigTest {

    @Test
    void prefixConfigProducesAPrefixRenamer() {
        var config = new RenamingConfig("p_", null);

        var renamer = config.toRenamer("topics");

        assertThat(renamer).isInstanceOf(PrefixRenamer.class);
        assertThat(renamer.rename("foo")).isEqualTo("p_foo");
    }

    @Test
    void mappingConfigProducesAMappingRenamer() {
        var config = new RenamingConfig(null, Map.of("foo", "bar"));

        var renamer = config.toRenamer("topics");

        assertThat(renamer).isInstanceOf(MappingRenamer.class);
        assertThat(renamer.rename("foo")).isEqualTo("bar");
    }

    @Test
    void rejectsNeitherPrefixNorMapping() {
        var config = new RenamingConfig(null, null);

        assertThatThrownBy(() -> config.toRenamer("groups"))
                .isInstanceOf(PluginConfigurationException.class)
                .hasMessageContaining("groups");
    }

    @Test
    void rejectsBothPrefixAndMapping() {
        var config = new RenamingConfig("p_", Map.of("foo", "bar"));

        assertThatThrownBy(() -> config.toRenamer("topics"))
                .isInstanceOf(PluginConfigurationException.class)
                .hasMessageContaining("topics");
    }
}
