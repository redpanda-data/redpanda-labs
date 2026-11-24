package demo.topicprefixer;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class PrefixRenamerTest {

    @Test
    void addsPrefixOnRename() {
        var renamer = new PrefixRenamer("p_");
        assertThat(renamer.rename("foo")).isEqualTo("p_foo");
    }

    @Test
    void stripsPrefixOnUnrename() {
        var renamer = new PrefixRenamer("p_");
        assertThat(renamer.unrename("p_foo")).isEqualTo("foo");
    }

    @Test
    void leavesInternalNameUntouchedInEitherDirection() {
        var renamer = new PrefixRenamer("p_");
        assertThat(renamer.rename("_schemas")).isEqualTo("_schemas");
        assertThat(renamer.unrename("_schemas")).isEqualTo("_schemas");
    }

    @Test
    void unrenameLeavesANameWithoutThePrefixUntouched() {
        var renamer = new PrefixRenamer("p_");
        assertThat(renamer.unrename("foo")).isEqualTo("foo");
    }

    @Test
    void emptyPrefixIsANoOpInBothDirections() {
        var renamer = new PrefixRenamer("");
        assertThat(renamer.rename("foo")).isEqualTo("foo");
        assertThat(renamer.unrename("foo")).isEqualTo("foo");
    }

    @Test
    void handlesNullAndEmptyNames() {
        var renamer = new PrefixRenamer("p_");
        assertThat(renamer.rename(null)).isNull();
        assertThat(renamer.rename("")).isEmpty();
        assertThat(renamer.unrename(null)).isNull();
        assertThat(renamer.unrename("")).isEmpty();
    }
}
