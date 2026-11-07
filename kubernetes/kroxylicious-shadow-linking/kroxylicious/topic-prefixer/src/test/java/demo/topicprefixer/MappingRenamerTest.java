package demo.topicprefixer;

import java.util.Map;

import io.kroxylicious.proxy.plugin.PluginConfigurationException;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class MappingRenamerTest {

    @Test
    void renamesAConfiguredNameForward() {
        var renamer = new MappingRenamer(Map.of("foo", "bar"));
        assertThat(renamer.rename("foo")).isEqualTo("bar");
    }

    @Test
    void unrenamesAConfiguredNameBackward() {
        var renamer = new MappingRenamer(Map.of("foo", "bar"));
        assertThat(renamer.unrename("bar")).isEqualTo("foo");
    }

    @Test
    void leavesUnconfiguredNamesUntouchedInEitherDirection() {
        var renamer = new MappingRenamer(Map.of("foo", "bar"));
        assertThat(renamer.rename("baz")).isEqualTo("baz");
        assertThat(renamer.unrename("baz")).isEqualTo("baz");
    }

    @Test
    void rejectsANonInvertibleMapping() {
        assertThatThrownBy(() -> new MappingRenamer(Map.of("foo", "shared", "baz", "shared")))
                .isInstanceOf(PluginConfigurationException.class)
                .hasMessageContaining("shared");
    }
}
