"""OpenAI Q&A with Retrieval Augmented Generation (RAG)."""

import os
import argparse
from langchain_core.runnables import RunnablePassthrough
from langchain_core.output_parsers import StrOutputParser
from langchain_mongodb import MongoDBAtlasVectorSearch
from langchain_openai import ChatOpenAI, OpenAIEmbeddings
from langchain.chains.chat_vector_db import prompts
from dotenv import load_dotenv

load_dotenv()


def main():
    """Run RAG pipeline."""

    parser = argparse.ArgumentParser()
    parser.add_argument("-q", "--query", type=str,
                        required=True, help="Ask me a question...")
    parser.add_argument("-k", "--top", type=int,
                        required=False, default=10)
    parser.add_argument("-r", "--retrieve", action="store_true", required=False,
                        help="Perform retrieval only, and skip generation.")
    parser.add_argument("-v", "--verbose", action="store_true", required=False,
                        help="Show the retrieved documents")
    args = parser.parse_args()

    vector_search = MongoDBAtlasVectorSearch.from_connection_string(
        os.getenv("ATLAS_CONNECTION_STRING"),
        f"{os.getenv("ATLAS_DB")}.{os.getenv("ATLAS_COLLECTION")}",
        OpenAIEmbeddings(model=os.getenv("OPENAI_EMBEDDING_MODEL")),
        index_name=os.getenv("ATLAS_INDEX")
    )

    if args.retrieve:
        # Retrieve similar documents only
        results = vector_search.similarity_search_with_score(
            query=args.query,
            k=args.top
        )
        for r in results:
            print(f"score: {r[1]}, text: {r[0].page_content[:500]}... \n\n")
        return

    # Retrieve and Generate
    retriever = vector_search.as_retriever(
        search_type="similarity",
        search_kwargs={"k": args.top, "score_threshold": 0.75}
    )
    llm = ChatOpenAI(model=os.getenv("OPENAI_MODEL"))
    initial_answer = llm.invoke(args.query)

    def format_docs(docs):
        return "\n".join(doc.page_content for doc in docs)

    # Build the RAG chain
    rag_chain = (
        {"context": retriever | format_docs, "question": RunnablePassthrough()}
        | prompts.QA_PROMPT
        | llm
        | StrOutputParser()
    )

    answer = rag_chain.invoke(args.query)
    print(f"\n Question: {args.query}")
    print(f"\n Initial answer: {initial_answer.content}")
    print(f"\n Augmented answer: {answer}")

    # Return source documents
    if args.verbose:
        documents = retriever.invoke(args.query)
        print("\nSource documents:")
        for d in documents:
            print(f"{d.page_content[:500]}... \n\n")


if __name__ == "__main__":
    main()
