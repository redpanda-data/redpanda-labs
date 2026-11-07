package demo.topicprefixer;

/**
 * Adds/strips a fixed prefix. Names starting with {@code _} (Redpanda's Schema Registry
 * {@code _schemas} topic, Kafka's own {@code __consumer_offsets}, etc.) are left untouched, so
 * infrastructure that relies on well-known names keeps working unmodified through the proxy.
 * <p>
 * An empty prefix is a valid, useful degenerate case: it renames nothing (in either direction), so
 * one target (topics or groups) can be configured with a real prefix while the other is left
 * completely alone.
 */
final class PrefixRenamer implements NameRenamer {

    private final String prefix;

    PrefixRenamer(String prefix) {
        this.prefix = prefix;
    }

    private boolean isRenamable(String name) {
        return name != null && !name.isEmpty() && !name.startsWith("_");
    }

    @Override
    public String rename(String realName) {
        return isRenamable(realName) ? prefix + realName : realName;
    }

    @Override
    public String unrename(String presentedName) {
        if (isRenamable(presentedName) && presentedName.startsWith(prefix)) {
            return presentedName.substring(prefix.length());
        }
        return presentedName;
    }
}
