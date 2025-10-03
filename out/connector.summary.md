# Vertex AI

File: `connector.rb`

Root keys: actions, connection, custom_action, custom_action_help, methods, object_definitions, pick_lists, test, title, triggers, version

Counts: **9** actions, **0** triggers, **56** methods

## Actions
- **batch_operation** (line 253)
- **classify_text** (line 484)
- **discover_index_config** (line 444)
- **find_neighbors** (line 655)
- **generate_embeddings** (line 734)
- **generate_text** (line 535)
- **read_index_datapoints** (line 672)
- **upsert_index_datapoints** (line 716)
- **vertex_operation** (line 355)

## Methods
- **add_upsert_ack** (line 1916)
- **add_word_count** (line 1927)
- **apply_template** (line 1942)
- **approx_token_count** (line 1953)
- **augment_vector_context** (line 1958)
- **behavior_registry** (line 1501)
- **build_endpoint_url** (line 1979)
- **build_generation_config** (line 2044)
- **build_headers** (line 2055)
- **build_payload** (line 791)
- **check_rate_limit** (line 2063)
- **chunk_by_tokens** (line 2081)
- **coerce_embeddings_to_datapoints** (line 2136)
- **coerce_kwargs** (line 2168)
- **confidence_from_distance** (line 2195)
- **configuration_registry** (line 1760)
- **debug_embedding_response** (line 1897)
- **deep_copy** (line 2216)
- **discover_index_config** (line 2218)
- **each_in_scope** (line 2252)
- **enrich_response** (line 1019)
- **error_hint** (line 2264)
- **execute_batch_behavior** (line 2347)
- **execute_behavior** (line 1802)
- **execute_pipeline** (line 1391)
- **extract_ids_for_read** (line 2281)
- **extract_response** (line 1046)
- **extract_user_config** (line 2308)
- **format_user_error** (line 2421)
- **get_behavior_input_fields** (line 2433)
- **get_behavior_output_fields** (line 2751)
- **http_request** (line 1109)
- **list_publisher_models** (line 2839)
- **memo_get** (line 2860)
- **memo_put** (line 2868)
- **memo_store** (line 2858)
- **normalize_find_neighbors** (line 2874)
- **normalize_http_error** (line 2932)
- **normalize_read_index_datapoints** (line 2971)
- **normalize_safety_settings** (line 2988)
- **parse_retry_after** (line 3021)
- **qualify_resource** (line 3030)
- **resolve_model_version** (line 3043)
- **retryable_http_code** (line 3060)
- **safe_mean** (line 3064)
- **select_model** (line 3071)
- **telemetry_envelope_fields** (line 3116)
- **to_query** (line 3143)
- **trace_fields** (line 3126)
- **transform_data** (line 1202)
- **validate_input** (line 1230)
- **value_present** (line 3166)
- **vector_search_base** (line 3174)
- **with_resilience** (line 1335)
- **wrap_embeddings_vectors** (line 3218)
- **wrap_embeddings_vectors_v1** (line 3193)

## Issues (12)
- [warning] **dynamic_call** at line 1477: Dynamic method dispatch via call(send) in method:execute_pipeline
- [info] **unused_method** at unknown loc: methods.debug_embedding_response is never called
- [info] **unused_method** at unknown loc: methods.add_upsert_ack is never called
- [info] **unused_method** at unknown loc: methods.add_word_count is never called
- [info] **unused_method** at unknown loc: methods.augment_vector_context is never called
- [info] **unused_method** at unknown loc: methods.coerce_kwargs is never called
- [info] **unused_method** at unknown loc: methods.normalize_find_neighbors is never called
- [info] **unused_method** at unknown loc: methods.normalize_read_index_datapoints is never called
- [info] **unused_method** at unknown loc: methods.to_query is never called
- [info] **unused_method** at unknown loc: methods.wrap_embeddings_vectors_v1 is never called
- [info] **unused_method** at unknown loc: methods.wrap_embeddings_vectors is never called
- [error] **method_cycle** at line 2848: methods cycle: list_publisher_models → resolve_model_version → build_endpoint_url → list_publisher_models

## Notes
- This summary is generated statically from source; no code was executed.
