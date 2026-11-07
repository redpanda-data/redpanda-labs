package demo.topicprefixer;

/**
 * Strategy for renaming one kind of name (a topic name, or a consumer group id) as it crosses the
 * proxy. {@link TopicPrefixerFilter} holds one renamer for topics and a separate one for consumer
 * groups, so each can be configured independently - see {@link RenamingConfig}.
 */
interface NameRenamer {

    /** The name to present to a client, given the real name on the backend. */
    String rename(String realName);

    /** The real name on the backend, given the name a client presented. */
    String unrename(String presentedName);
}
