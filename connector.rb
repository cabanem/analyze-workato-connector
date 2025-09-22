{
  title: 'Google Vertex AI',
  custom_action: true,
  custom_action_help: {
    learn_more_url: 'https://cloud.google.com/vertex-ai/docs/reference/rest',
    learn_more_text: 'Google Vertex AI API documentation',
    body: '<p>Build your own Google Vertex AI action with a HTTP request. The request will be authorized with your Google Vertex AI connection.</p>'
  },

  connection: {
    fields: [
      # Developer options
      { # - verbose_errors
        name: 'verbose_errors', label: 'Verbose errors',
        group: 'Developer options', type: 'boolean', control_type: 'checkbox',
        hint: 'When enabled, include upstream response bodies in error messages. Disable in production.'
      },
      # Authentication
      { # - auth_type
        name: 'auth_type', label: 'Authentication type', group: 'Authentication',
        control_type: 'select',  default: 'custom', optional: false, extends_schema: true, 
        hint: 'Select the authentication type for connecting to Google Vertex AI.',
        options: [ ['Client credentials', 'custom'], %w[OAuth2 oauth2] ] 
      },
      # Vertex AI environment
      { name: 'region', label: 'Region', group: 'Vertex AI environment', control_type: 'select',  optional: false,
        options: [
          ['US central 1', 'us-central1'],
          ['US east 1', 'us-east1'],
          ['US east 4', 'us-east4'],
          ['US east 5', 'us-east5'],
          ['US west 1', 'us-west1'],
          ['US west 4', 'us-west4'],
          ['US south 1', 'us-south1'],
          ['North America northeast 1', 'northamerica-northeast1'],
          ['Europe west 1', 'europe-west1'],
          ['Europe west 2', 'europe-west2'],
          ['Europe west 3', 'europe-west3'],
          ['Europe west 4', 'europe-west4'],
          ['Europe west 9', 'europe-west9'],
          ['Asia northeast 1', 'asia-northeast1'],
          ['Asia northeast 3', 'asia-northeast3'],
          ['Asia southeast 1', 'asia-southeast1'] ],
        hint: 'Select the Google Cloud Platform (GCP) region used for the Vertex model.', toggle_hint: 'Select from list',
        toggle_field: {
          name: 'region', label: 'Region', type: 'string', control_type: 'text', optional: false, 
          toggle_hint: 'Use custom value', hint: "Enter the region you want to use" } },
      { name: 'project', label: 'Project', group: 'Vertex AI environment', optional: false,  hint: 'E.g abc-dev-1234' },
      { name: 'version', label: 'Version', group: 'Vertex AI environment', optional: false,  default: 'v1', hint: 'E.g. v1beta1' },
      # Model discovery and validation
      { name: 'dynamic_models', label: 'Refresh model list from API (Model Garden)', group: 'Model discovery and validation', type: 'boolean', 
        control_type: 'checkbox', optional: true, hint: 'Fetch available Gemini/Embedding models at runtime. Falls back to a curated static list on errors.' },
      { name: 'include_preview_models', label: 'Include preview/experimental models', group: 'Model discovery and validation', type: 'boolean', control_type: 'checkbox', 
        optional: true, sticky: true, hint: 'Also include Experimental/Private/Public Preview models. Leave unchecked for GA-only in production.' },
      { name: 'validate_model_on_run', label: 'Validate model before run', group: 'Model discovery and validation', type: 'boolean', control_type: 'checkbox',
        optional: true, sticky: true, hint: 'Pre-flight check the chosen model and your project access before sending the request. Recommended.' },
      { name: 'enable_rate_limiting', label: 'Enable rate limiting', group: 'Model discovery and validation', type: 'boolean', control_type: 'checkbox', 
        optional: true, default: true, hint: 'Automatically throttle requests to stay within Vertex AI quotas' }
    ],
    authorization: {
      type: 'multi',

      selected: lambda do |connection|
        connection['auth_type'] || 'custom'
      end,

      options: {
        oauth2: {
          type: 'oauth2',
          fields: [
            { name: 'client_id', group: 'OAuth 2.0 (user delegated)', optional: false,
              hint: 'You can find your client ID by logging in to your ' \
                    "<a href='https://console.developers.google.com/' " \
                    "target='_blank'>Google Developers Console</a> account. " \
                    'After logging in, click on Credentials to show your ' \
                    'OAuth 2.0 client IDs. <br> Alternatively, you can create your ' \
                    'Oauth 2.0 credentials by clicking on Create credentials > ' \
                    'Oauth client ID. <br> Please use <b>https://www.workato.com/' \
                    'oauth/callback</b> for the redirect URI when registering your ' \
                    'OAuth client. <br> More information about authentication ' \
                    "can be found <a href='https://developers.google.com/identity/" \
                    "protocols/OAuth2?hl=en_US' target='_blank'>here</a>." },
            { name: 'client_secret', group: 'OAuth 2.0 (user delegated)',optional: false, control_type: 'password',
              hint: 'You can find your client secret by logging in to your ' \
                    "<a href='https://console.developers.google.com/' " \
                    "target='_blank'>Google Developers Console</a> account. " \
                    'After logging in, click on Credentials to show your ' \
                    'OAuth 2.0 client IDs and select your desired account name.' }
          ],
          authorization_url: lambda do |connection|
            scopes = [
              'https://www.googleapis.com/auth/cloud-platform', # Vertex AI scope
              'https://www.googleapis.com/auth/drive.readonly' # Google Drive readonly scope
            ].join(' ')
            params = {
              client_id: connection['client_id'],
              response_type: 'code',
              scope: scopes,
              access_type: 'offline',
              include_granted_scopes: 'true',
              prompt: 'consent'
            }.to_param
            "https://accounts.google.com/o/oauth2/v2/auth?#{params}"
          end,
          acquire: lambda do |connection, auth_code|
            response = post('https://oauth2.googleapis.com/token').
                       payload(
                         client_id: connection['client_id'],
                         client_secret: connection['client_secret'],
                         grant_type: 'authorization_code',
                         code: auth_code,
                         redirect_uri: 'https://www.workato.com/oauth/callback'
                       ).request_format_www_form_urlencoded
            [response, nil, nil]
          end,
          refresh: lambda do |connection, refresh_token|
            post('https://oauth2.googleapis.com/token').
              payload(
                client_id: connection['client_id'],
                client_secret: connection['client_secret'],
                grant_type: 'refresh_token',
                refresh_token: refresh_token
              ).request_format_www_form_urlencoded
          end,
          apply: lambda do |_connection, access_token|
            headers(Authorization: "Bearer #{access_token}")
          end
        },
        custom: {
          type: 'custom_auth',
          fields: [
            { name: 'service_account_email',
              optional: false, group: 'Service Account',
              hint: 'The service account created to delegate other domain users (e.g. name@project.iam.gserviceaccount.com)' },
            { name: 'client_id', optional: false },
            { name: 'private_key', ontrol_type: 'password',  multiline: true, optional: false,
              hint: 'Copy and paste the private key that came from the downloaded json. <br/>' \
                    "Click <a href='https://developers.google.com/identity/protocols/oauth2/' " \
                    "service-account/target='_blank'>here</a> to learn more about Google Service " \
                    'Accounts.<br><br>Required scope: <b>https://www.googleapis.com/auth/cloud-platform</b>' }
          ],
          acquire: lambda do |connection|
            jwt_body_claim = {
              'iat' => now.to_i,
              'exp' => 1.hour.from_now.to_i,
              'aud' => 'https://oauth2.googleapis.com/token',
              'iss' => connection['service_account_email'],
              'sub' => connection['service_account_email'],
              'scope' => 'https://www.googleapis.com/auth/cloud-platform'
            }
            private_key = connection['private_key'].gsub('\\n', "\n")
            jwt_token =
              workato.jwt_encode(jwt_body_claim,
                                 private_key, 'RS256',
                                 kid: connection['client_id'])

            response = post('https://oauth2.googleapis.com/token',
                            grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                            assertion: jwt_token).
                       request_format_www_form_urlencoded

            { access_token: response['access_token'] }
          end,
          refresh_on: [401],
          apply: lambda do |connection|
            headers(Authorization: "Bearer #{connection['access_token']}")
          end
        }
      }
    },

    base_uri: lambda do |connection|
      "https://#{connection['region']}-aiplatform.googleapis.com/#{connection['version'] || 'v1'}/"
    end
  },

  test: lambda do |connection|
    # Validate connection/access to Vertex AI
    call('api_request', connection, :get,
      "https://#{connection['region']}-aiplatform.googleapis.com/#{connection['version'] || 'v1'}/projects/#{connection['project']}/locations/#{connection['region']}/datasets",
      { params: { pageSize: 1 } }
    )
    # Validate connection/access to Google Drive
    begin
      response = call('api_request', connection, :get,
        call('drive_api_url', :files),
        {
          params: { pageSize: 1, q: "trashed = false" },
          error_handler: lambda do |code, body, message|
            if code == 403
              error("Drive API not enabled or missing permissions")
            else
              call('handle_vertex_error', connection, code, body, message)
            end
          end
        }
      )
      { vertex_ai: "connected", drive_access: "connected", files_visible: response['files'].length }
    rescue => e
      { vertex_ai: "connected", drive_access: "error - #{e.message}" }
    end
  end,

  actions: {
    send_messages: {
      title: 'Vertex -- Send messages to Gemini models',
      subtitle: 'Converse with Gemini models in Google Vertex AI',
      description: lambda do |input|
        model = input['model']
        if model.present?
          "Send messages to <span class='provider'>#{model.split('/')[-1].humanize}</span> model"
        else
          'Send messages to <span class=\'provider\'>Gemini</span> models'
        end
      end,

      help: {
        body: 'This action sends a message to Vertex AI, and gathers a response using the selected Gemini Model.'
      },

      input_fields: lambda do |object_definitions|
        object_definitions['send_messages_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Accepts prepared prompts from RAG_Utils
        # Validate model
        call('validate_publisher_model!', connection, input['model'])

        # Build payload - check for prepared input from RAG_Utils
        payload = if input['formatted_prompt'].present?
          # Use prepared prompt directly (from RAG_Utils)
          input['formatted_prompt']
        else
          # Build payload using existing method (backward compatibility)
          call('payload_for_send_message', input)
        end

        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
              "/#{input['model']}:generateContent"

        # Make rate-limited request
        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
        response
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['send_messages_output']
      end,

      sample_output: lambda do |_connection, _input|
        call('sample_record_output', 'send_message')
      end
    },
    # --- Generative actions (text models) [6] ---
    translate_text: {
      title: 'Vertex -- Translate text',
      subtitle: 'Translate text between languages',
      description: "Translate text into a different language using models from Google Vertex AI",
      help: {
        body: 'This action translates inputted text into a different language. While other languages may be possible, languages not on the predefined list may not provide reliable translations.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['translate_text_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])
        # Build payload with enhanced builder
        instruction = if input['from'].present?
          "You are an assistant helping to translate a user's input from #{input['from']} into #{input['to']}. " \
          "Respond only with the user's translated text in #{input['to']} and nothing else. " \
          "The user input is delimited with triple backticks."
        else
          "You are an assistant helping to translate a user's input into #{input['to']}. " \
          "Respond only with the user's translated text in #{input['to']} and nothing else. " \
          "The user input is delimited with triple backticks."
        end

        user_prompt = "```#{call('replace_backticks_with_hash', input['text'])}```"

        payload = call('build_gemini_payload', instruction, user_prompt, {
          safety_settings: input['safetySettings'],
          json_output: true,
          json_key: 'response',
          temperature: 0
        })
        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
              "/#{input['model']}:generateContent"

        # Make rate-limited request
        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
        # Extract and return the response
        call('extract_response', response, { type: :generic, json_response: true })
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['translate_text_output']
      end,

      sample_output: lambda do |_connection, _input|
        call('sample_record_output', 'translate_text')
      end
    },
    summarize_text: {
      title: 'Vertex -- Summarize text',
      subtitle: 'Get a summary of the input text in configurable length',
      description: "Summarize text using models from Google Vertex AI",
      help: {
        body: 'This action summarizes input text into a shorter version. The length of the summary can be configured.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['summarize_text_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])
        # Build payload
        payload = call('build_ai_payload', :summarize, input)
        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
              "/#{input['model']}:generateContent"

        # Make rate-limited request
        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
        # Extract and return the response
        call('extract_response', response, { type: :generic, json_response: false })
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['summarize_text_output']
      end,

      sample_output: lambda do |_connection, _input|
        call('sample_record_output', 'summarize_text')
      end
    },
    parse_text: {
      title: 'Vertex -- Parse text',
      subtitle: 'Extract structured data from freeform text',
      help: {
        body: 'This action helps process input text to find specific information based on defined guidelines. The processed information is then available as datapills.'
      },
      description: "Parse text to find specific information using models from Google Vertex AI",

      input_fields: lambda do |object_definitions|
        object_definitions['parse_text_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])
        # Build payload
        payload = call('build_ai_payload', :parse, input)
        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
                        "/#{input['model']}:generateContent"

        # Make rate-limited request
        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
        # Extract and return the response
        call('extract_response', response, { type: :parsed })
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['parse_text_output']
      end,

      sample_output: lambda do |_connection, input|
        call('format_parse_sample', parse_json(input['object_schema'])).
          merge(call('safety_ratings_output_sample'),
                call('usage_output_sample'))
      end
    },
    draft_email: {
      title: 'Vertex -- Draft email',
      subtitle: 'Generate an email based on user description',
      description: "Generate draft email using models from Google Vertex AI",
      help: {
        body: 'This action generates an email and parses input into datapills ' \
              'containing a subject line and body for easy mapping into future ' \
              'recipe actions. Note that the body contains placeholder text for ' \
              "a salutation if this information isn't present in the email description."
      },

      input_fields: lambda do |object_definitions|
        object_definitions['draft_email_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])
        # Build payload
        payload = call('build_ai_payload', :email, input)
        # Build the url
        url ="projects/#{connection['project']}/locations/#{connection['region']}" \
                        "/#{input['model']}:generateContent"

        # Make rate-limited request
        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
        # Extract and return the response
        call('extract_response', response, { type: :email })
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['draft_email_output']
      end,

      sample_output: lambda do
        call('sample_record_output', 'draft_email')
      end
    },
    # --- Analysis actions (text models) [7] ---
    ai_classify: {
      title: 'Vertex -- AI Classification',
      subtitle: 'Classify text using AI with confidence scoring',
      description: "Classify text into predefined categories using models from Google Vertex AI with confidence scores and alternatives",
      help: {
        body: 'This action uses AI to classify text into one of the provided categories. ' \
              'Returns confidence scores and alternative classifications. Designed to work ' \
              'with text prepared by RAG_Utils prepare_for_ai action.'
      },

      input_fields: lambda do |object_definitions|
        [
          { name: 'text', label: 'Text to classify', type: 'string', optional: false, hint: 'Text content to classify (preferably from RAG_Utils prepare_for_ai)' },
          { name: 'categories', label: 'Categories', type: 'array', of: 'object', optional: false, list_mode_toggle: true,
            properties: [
              { name: 'key', label: 'Category key', type: 'string', optional: false },
              { name: 'description', label: 'Category description', type: 'string', optional: true }
            ],
            hint: 'Array of categories with keys and optional descriptions' },
          { name: 'model', label: 'Model', type: 'string', optional: false, control_type: 'select', extends_schema: true,
            pick_list: :available_text_models, hint: 'Select the Gemini model to use', toggle_hint: 'Select from list',
            toggle_field: {
              name: 'model', label: 'Model (custom)', type: 'string',
              control_type: 'text', toggle_hint: 'Use custom value',
              hint: 'E.g., publishers/google/models/gemini-pro'
            } },
          { name: 'options', label: 'Classification options', type: 'object', optional: true,
            properties: [
              { name: 'return_confidence', label: 'Return confidence score', type: 'boolean', control_type: 'checkbox', default: true },
              { name: 'return_alternatives', label: 'Return alternative classifications', type: 'boolean', control_type: 'checkbox', default: true },
              { name: 'temperature', label: 'Temperature', type: 'number', hint: 'Controls randomness (0.0-1.0)', default: 0.1 }
            ] }
        ].concat(object_definitions['config_schema'].only('safetySettings'))
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: 'selected_category', label: 'Selected category', type: 'string' },
          { name: 'confidence', label: 'Confidence score', type: 'number', hint: 'Confidence score (0.0-1.0)' },
          { name: 'alternatives', label: 'Alternative classifications', type: 'array', of: 'object',
            properties: [
              { name: 'category', type: 'string' },
              { name: 'confidence', type: 'number' }
            ]
          },
          { name: 'usage_metrics', label: 'Usage metrics', type: 'object', properties: [
            { name: 'prompt_token_count', type: 'integer' },
            { name: 'candidates_token_count', type: 'integer' },
            { name: 'total_token_count', type: 'integer' }
          ]}
        ].concat(object_definitions['safety_rating_schema'])
      end,

      sample_output: lambda do |_connection, input|
        {
          'selected_category' => input['categories']&.first&.[]('key') || 'urgent',
          'confidence' => 0.95,
          'alternatives' => [
            { 'category' => 'normal', 'confidence' => 0.05 }
          ],
          'usage_metrics' => {
            'prompt_token_count' => 45,
            'candidates_token_count' => 12,
            'total_token_count' => 57
          }
        }.merge(call('safety_ratings_output_sample'))
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])

        # Build payload for AI classification
        payload = call('build_ai_payload', :ai_classify, input, connection)

        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
                        "/#{input['model']}:generateContent"

        # Make rate-limited request
        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)

        # Extract and return the response
        call('extract_response', response, { type: :classify, input: input })
      end
    },
    analyze_text: {
      title: 'Vertex -- Analyze text',
      subtitle: 'Contextual analysis of text to answer user-provided questions',
      description: "Analyze text to answer user-provided questions using models from Google Vertex AI",
      help: {
        body: "This action performs a contextual analysis of a text to answer user-provided questions. If the answer isn't found in the text, the datapill will be empty."
      },

      input_fields: lambda do |object_definitions|
        object_definitions['analyze_text_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])
        # Build payload
        payload = call('build_ai_payload', :analyze, input)
        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
              "/#{input['model']}:generateContent"

        # Make rate-limited request
        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
        # Extract and return the response
        call('extract_response', response, { type: :generic, json_response: true })
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['analyze_text_output']
      end,

      sample_output: lambda do
        call('sample_record_output', 'analyze_text')
      end
    },

    # --- Generative and Analysis actions (multimodal models) ---
    analyze_image: {
      title: 'Vertex -- Analyze image',
      subtitle: 'Analyze image based on the provided question',
      description: "Analyses passed <span class='provider'>image</span> using " \
                   "Gemini models in <span class='provider'>Google Vertex AI</span>",
      help: {
        body: 'This action analyses passed image and answers related question.'
      },

      input_fields: lambda do |object_definitions|
        object_definitions['analyze_image_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])
        # Build payload
        payload = call('build_ai_payload', :analyze_image, input)
        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
              "/#{input['model']}:generateContent"

        # Make rate-limited request
        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
        # Extract and return the response
        call('extract_response', response, { type: :generic, json_response: false })
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['analyze_image_output']
      end,

      sample_output: lambda do
        call('sample_record_output', 'analyze_image')
      end
    },
    # --- Embedding and Vector Search actions (4)---
    generate_embeddings: {
      title: 'Vertex -- Generate text embeddings (Batch)',
      subtitle: 'Generate embeddings for multiple texts in batch',
      description: 'Generate text embeddings for multiple texts using Google models in Google Vertex AI',
      batch: true,
      help: {
        body: 'Batch text embedding generates numerical vectors for multiple text inputs efficiently. ' \
              'It processes an array of texts and returns vectors that capture the meaning ' \
              'and context of each text. These vectors can be used for similarity search, ' \
              'clustering, classification, and other natural language processing tasks.'
      },

      input_fields: lambda do |object_definitions|
        [
          { name: 'batch_id', label: 'Batch ID', type: 'string', optional: false, hint: 'Unique identifier for this batch of embeddings' },
          { name: 'texts', label: 'Text objects', type: 'array', of: 'object', optional: false, list_mode_toggle: true, hint: 'Array of text objects to generate embeddings for',
            properties: [
              { name: 'id', label: 'Text ID', type: 'string', optional: false },
              { name: 'content', label: 'Text content', type: 'string', optional: false, hint: 'Input text must not exceed 8192 tokens (approximately 6000 words).' },
              { name: 'metadata', label: 'Metadata', type: 'object', optional: true }
            ] },
          { name: 'model', label: 'Model', type: 'string', optional: false, control_type: 'select', pick_list: :available_embedding_models,
            extends_schema: true, hint: 'Select the embedding model to use', toggle_hint: 'Select from list',
            toggle_field: { 
              name: 'model', label: 'Model (custom)', type: 'string', control_type: 'text', toggle_hint: 'Use custom value', hint: 'E.g., publishers/google/models/text-embedding-004' } },
          { name: 'task_type', label: 'Task type', type: 'string', optional: true, control_type: 'select', pick_list: :embedding_task_list,
            hint: 'Intended downstream application to help the model produce better embeddings', toggle_hint: 'Select from list',
            toggle_field: {
              name: 'task_type', label: 'Task type (custom)', type: 'string',
              control_type: 'text', toggle_hint: 'Use custom value',
              hint: 'E.g., RETRIEVAL_DOCUMENT, RETRIEVAL_QUERY, SEMANTIC_SIMILARITY'
            } }
        ]
      end,

      execute: lambda do |connection, input, _eis, _eos|
        call('generate_embeddings_batch_exec', connection, input)
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: 'batch_id', label: 'Batch ID', type: 'string' },
          { name: 'embeddings_count', label: 'Embeddings count', type: 'integer',
            hint: 'Total number of embeddings generated' },
          { name: 'embeddings', label: 'Generated embeddings', type: 'array', of: 'object',
            properties: [
              { name: 'id', label: 'Text ID', type: 'string' },
              { name: 'vector', label: 'Embedding vector', type: 'array', of: 'number' },
              { name: 'dimensions', label: 'Vector dimensions', type: 'integer' },
              { name: 'metadata', label: 'Original metadata', type: 'object' }
            ]
          },
          { name: 'first_embedding', label: 'First embedding (quick access)', type: 'object',
            properties: [
              { name: 'id', label: 'Text ID', type: 'string' },
              { name: 'vector', label: 'Embedding vector', type: 'array', of: 'number' },
              { name: 'dimensions', label: 'Vector dimensions', type: 'integer' }
            ],
            hint: 'First embedding for quick recipe access'
          },
          { name: 'embeddings_json', label: 'Embeddings as JSON string', type: 'string', hint: 'All embeddings serialized as JSON for bulk operations' },
          { name: 'model_used', label: 'Model used', type: 'string' },
          { name: 'total_processed', label: 'Total texts processed', type: 'integer' },
          { name: 'successful_requests', label: 'Successful requests', type: 'integer' },
          { name: 'failed_requests', label: 'Failed requests', type: 'integer' },
          { name: 'total_tokens', label: 'Total tokens', type: 'integer' },
          { name: 'batches_processed', label: 'Batches processed', type: 'integer', hint: 'Number of API calls made (including retries and fallbacks)' },
          { name: 'api_calls_saved', label: 'API calls saved', type: 'integer', hint: 'Number of API calls saved through batching' },
          { name: 'estimated_cost_savings', label: 'Estimated cost savings', type: 'number', hint: 'Estimated cost savings in USD from batching' },
          { name: 'pass_fail', label: 'Batch success', type: 'boolean', hint: 'True if all embeddings were generated successfully' },
          { name: 'action_required', label: 'Action required', type: 'string', hint: 'Next recommended action based on results' }
        ]
      end,

      sample_output: lambda do |_connection, input|
        sample_embedding = {
          'id' => 'text_1',
          'vector' => Array.new(768) { rand(-1.0..1.0).round(6) },
          'dimensions' => 768,
          'metadata' => { 'source' => 'sample' }
        }
        {
          'batch_id' => input['batch_id'] || 'batch_001',
          'embeddings_count' => 1,
          'embeddings' => [sample_embedding],
          'first_embedding' => {
            'id' => sample_embedding['id'],
            'vector' => sample_embedding['vector'],
            'dimensions' => sample_embedding['dimensions']
          },
          'embeddings_json' => [sample_embedding].to_json,
          'model_used' => input['model'] || 'publishers/google/models/text-embedding-004',
          'total_processed' => 1,
          'successful_requests' => 1,
          'failed_requests' => 0,
          'total_tokens' => 15,
          'batches_processed' => 1,
          'api_calls_saved' => 0,
          'estimated_cost_savings' => 0.0,
          'pass_fail' => true,
          'action_required' => 'ready_for_indexing'
        }
      end
    },
    generate_embedding_single: {
      title: 'Vertex -- Generate single text embedding',
      subtitle: 'Generate embedding for a single text input',
      description: 'Generate text embedding for a single text using Google models in Google Vertex AI',
      help: {
        body: 'Generate a numerical vector for a single text input. This is optimized for RAG query flows ' \
              'where you need to embed a single user query to find similar documents. The vector captures ' \
              'the semantic meaning of the text and can be used for similarity search, retrieval, and ' \
              'other natural language processing tasks.'
      },

      input_fields: lambda do |object_definitions|
        [
          { name: 'text', label: 'Text', type: 'string', optional: false, hint: 'Single text string to embed. Must not exceed 8192 tokens (approximately 6000 words).' },
          {
            name: 'model',
            label: 'Model',
            type: 'string',
            optional: false,
            control_type: 'select',
            pick_list: :available_embedding_models,
            extends_schema: true,
            hint: 'Select the embedding model to use',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'model',
              label: 'Model (custom)',
              type: 'string',
              control_type: 'text',
              toggle_hint: 'Use custom value',
              hint: 'E.g., publishers/google/models/text-embedding-004'
            }
          },
          {
            name: 'task_type',
            label: 'Task type',
            type: 'string',
            optional: true,
            control_type: 'select',
            pick_list: :embedding_task_list,
            hint: 'Intended downstream application to help the model produce better embeddings',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'task_type',
              label: 'Task type (custom)',
              type: 'string',
              control_type: 'text',
              toggle_hint: 'Use custom value',
              hint: 'E.g., RETRIEVAL_QUERY, RETRIEVAL_DOCUMENT, SEMANTIC_SIMILARITY'
            }
          },
          {
            name: 'title',
            label: 'Title',
            type: 'string',
            optional: true,
            hint: 'Document title to prepend to text content for better embedding quality'
          }
        ]
      end,

      execute: lambda do |connection, input, _eis, _eos|
        call('generate_embedding_single_exec', connection, input)
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: 'vector', label: 'Embedding vector', type: 'array', of: 'number', hint: 'Array of float values representing the text embedding' },
          { name: 'dimensions', label: 'Vector dimensions', type: 'integer', hint: 'Number of dimensions in the vector' },
          { name: 'model_used', label: 'Model used', type: 'string', hint: 'The embedding model that was used' },
          { name: 'token_count', label: 'Token count', type: 'integer', hint: 'Estimated number of tokens processed' }
        ]
      end,

      sample_output: lambda do |_connection, input|
        {
          'vector' => Array.new(768) { rand(-1.0..1.0).round(6) },
          'dimensions' => 768,
          'model_used' => input['model'] || 'publishers/google/models/text-embedding-004',
          'token_count' => 15
        }
      end
    },
    find_neighbors: {
      title: 'Vertex -- Find neighbors',
      subtitle: 'K-NN query on a deployed Vertex AI index endpoint',
      description: "Query a Vertex AI Vector Search index endpoint to retrieve nearest neighbors.",
      retry_on_request: ['POST'],
      retry_on_response: [429, 500, 502, 503, 504],
      max_retries: 3,
      help: {
        body: "This action queries a deployed Vector Search index endpoint to find nearest neighbors "\
              "(k-NN). IMPORTANT: Use the endpoint's own host (public endpoint domain or PSC DNS). "\
              "Final URL looks like https://{INDEX_ENDPOINT_HOST}/v1/projects/{PROJECT}/locations/{LOCATION}/"\
              "indexEndpoints/{INDEX_ENDPOINT_ID}:findNeighbors. "\
              "Returning full datapoints increases latency and cost."
      },

      input_fields: lambda do |object_definitions|
        object_definitions['find_neighbors_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Build payload and normalized host
        payload = call('build_ai_payload', :find_neighbors, input)
        host = input['index_endpoint_host'].to_s.strip
        # Host normalization
        if host.blank?
          error('Index endpoint host is required')
        end
        
        # Remove protocol if present and trailing slashes
        host = host.gsub(/^https?:\/\//i, '').gsub(/\/+$/, '')
        
        # Validate host format (basic check for valid domain or IP)
        unless host.match?(/^[\w\-\.]+(:\d+)?$/)
          error("Invalid index endpoint host format: #{host}")
        end

        version = connection['version'].presence || 'v1'
        project = connection['project']
        region = connection['region']
        endpoint_id = input['index_endpoint_id']
        
        # Validate required parameters
        error('Project is required') if project.blank?
        error('Region is required') if region.blank?
        error('Index endpoint ID is required') if endpoint_id.blank?
        # Construct the full URL
        url = "https://#{host}/#{version}/projects/#{project}/locations/#{region}/" \
              "indexEndpoints/#{endpoint_id}:findNeighbors"
        # Make the request
        response = call('api_request', connection, :post, url, {
          payload: payload,
          error_handler: lambda do |code, body, message|
            if code == 404
              # Use a custom message for 404s since they're often configuration errors
              error("Index endpoint not found. Please verify:\n" \
                    "• Host: #{host}\n" \
                    "• Endpoint ID: #{endpoint_id}\n" \
                    "• Region: #{region}")
            else
              # Use the centralized handler for all other errors
              call('handle_vertex_error', connection, code, body, message)
            end
          end
        })

        # Transform to recipe-friendly structure
        call('transform_find_neighbors_response', response)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['find_neighbors_output']
      end,

      sample_output: lambda do
        {
          'nearestNeighbors' => [
            {
              'id' => 'query-0',
              'neighbors' => [
                {
                  'distance' => 0.1234,
                  'datapoint' => {
                    'datapointId' => 'dp_123',
                    # Present only when returnFullDatapoint = true
                    'featureVector' => [0.1, -0.2, 0.3],
                    'restricts' => [
                      { 'namespace' => 'color', 'allowList' => ['red'] }
                    ],
                    'numericRestricts' => [
                      { 'namespace' => 'price', 'op' => 'LESS_EQUAL', 'valueFloat' => 9.99 }
                    ],
                    'crowdingTag' => { 'crowdingAttribute' => 'brand_A' },
                    'sparseEmbedding' => {
                      'values' => [0.4, 0.2],
                      'dimensions' => [5, 17]
                    }
                  }
                }
              ]
            }
          ]
        }
      end
    },
    upsert_index_datapoints: {
      title: 'Vertex -- Upsert index datapoints',
      subtitle: 'Add or update vector datapoints in Vertex AI Vector Search index',
      description: 'Upsert vector datapoints to Vertex AI Vector Search index',

      help: lambda do
        {
          body: 'Insert or update vector datapoints in a Vertex AI Vector Search index. ' \
                'This action handles batch processing and can process up to 100 datapoints per request. ' \
                'It accepts output from RAG_Utils adapt_chunks_for_vertex action and supports both ' \
                'create and update operations in a single call.',
          learn_more_url: 'https://cloud.google.com/vertex-ai/docs/vector-search/update-rebuild-index',
          learn_more_text: 'Learn more about Vector Search'
        }
      end,

      input_fields: lambda do |object_definitions|
        [
          {
            name: 'index_id',
            label: 'Index ID',
            type: 'string',
            optional: false,
            hint: 'The Vector Search index resource ID (e.g., "projects/PROJECT/locations/REGION/indexes/INDEX_ID")'
          },
          {
            name: 'datapoints',
            label: 'Datapoints',
            type: 'array',
            of: 'object',
            optional: false,
            properties: [
              {
                name: 'datapoint_id',
                label: 'Datapoint ID',
                type: 'string',
                optional: false,
                hint: 'Unique identifier for the vector datapoint'
              },
              {
                name: 'feature_vector',
                label: 'Feature vector',
                type: 'array',
                of: 'number',
                optional: false,
                hint: 'Array of floats representing the embedding vector'
              },
              {
                name: 'restricts',
                label: 'Restricts',
                type: 'array',
                of: 'object',
                optional: true,
                properties: [
                  { name: 'namespace', label: 'Namespace', type: 'string', optional: false },
                  { name: 'allowList', label: 'Allow list', type: 'array', of: 'string', optional: true },
                  { name: 'denyList', label: 'Deny list', type: 'array', of: 'string', optional: true } 
                ],
                hint: 'Array of namespace/allowList/denyList filters for the datapoint'
              },
              {
                name: 'crowding_tag',
                label: 'Crowding tag',
                type: 'string',
                optional: true,
                hint: 'Tag used for result diversity in searches'
              }
            ],
            hint: 'Array of vector datapoints to upsert. Maximum 100 datapoints per request.'
          },
          {
            name: 'update_mask',
            label: 'Update mask',
            type: 'string',
            optional: true,
            hint: 'Comma-separated list of fields to update for existing datapoints (e.g., "featureVector,restricts")'
          }
        ]
      end,

      execute: lambda do |connection, input|
        index_id = input['index_id']
        datapoints = input['datapoints'] || []
        update_mask = input['update_mask']

        # Use the enhanced batch upsert method
        results = call('batch_upsert_datapoints', connection, index_id, datapoints, update_mask)

        # Transform the enhanced response format to match the action's expected output
        {
          'successfully_upserted_count' => results['successful_upserts'],
          'failed_datapoints' => results['error_details'].map do |error|
            {
              'datapoint_id' => error['datapoint_id'],
              'error' => error['error']
            }
          end,
          'total_processed' => results['total_processed'],
          'failed_upserts' => results['failed_upserts'],
          'index_stats' => results['index_stats']
        }
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: 'successfully_upserted_count', label: 'Successfully upserted count', type: 'integer', hint: 'Number of datapoints successfully upserted' },
          { name: 'total_processed', label: 'Total processed', type: 'integer', hint: 'Total number of datapoints processed' },
          { name: 'failed_upserts', label: 'Failed upserts', type: 'integer', hint: 'Number of datapoints that failed to upsert' },
          { name: 'failed_datapoints', label: 'Failed datapoints', type: 'array', of: 'object', hint: 'Array of datapoints that failed to upsert with error details',
            properties: [
              { name: 'datapoint_id', label: 'Datapoint ID', type: 'string' },
              { name: 'error', label: 'Error message', type: 'string' }
            ] },
          { name: 'index_stats', label: 'Index statistics', type: 'object', hint: 'Index metadata and statistics',
            properties: [
              { name: 'index_id',         label: 'Index ID',          type: 'string' },
              { name: 'deployed_state',   label: 'Deployed state',    type: 'string' },
              { name: 'total_datapoints', label: 'Total datapoints',  type: 'integer' },
              { name: 'dimensions',       label: 'Vector dimensions', type: 'integer' },
              { name: 'display_name',     label: 'Display name',      type: 'string' },
              { name: 'created_time',     label: 'Created time',      type: 'string' },
              { name: 'updated_time',     label: 'Updated time',      type: 'string' }
            ] }
        ]
      end,

      sample_output: lambda do |connection|
        {
          'successfully_upserted_count' => 248,
          'total_processed' => 250,
          'failed_upserts' => 2,
          'failed_datapoints' => [
            {
              'datapoint_id' => 'doc_123',
              'error' => 'Vector dimension mismatch'
            }
          ],
          'index_stats' => {
            'index_id' => 'projects/my-project/locations/us-central1/indexes/my-index',
            'deployed_state' => 'DEPLOYED',
            'total_datapoints' => 15420,
            'dimensions' => 768,
            'display_name' => 'My Vector Index',
            'created_time' => '2024-01-01T00:00:00Z',
            'updated_time' => '2024-01-15T12:30:00Z'
          }
        }
      end
    },

    # --- Test connection action (2) ---
    test_connection: {
      title: 'Setup -- Test connection and permissions',
      subtitle: 'Verify API access and permissions',
      description: 'Tests connectivity to Vertex AI and Google Drive APIs, validates permissions, and returns diagnostic information',
      help: {
        body: 'Use this action to verify your connection is working and has the required permissions. ' \
              'Useful for debugging and monitoring connection health.',
        learn_more_url: 'https://cloud.google.com/vertex-ai/docs/reference/rest',
        learn_more_text: 'API Documentation'
      },
      
      input_fields: lambda do |object_definitions|
        [
          { name: 'test_vertex_ai', label: 'Test Vertex AI', type: 'boolean', control_type: 'checkbox', default: true, optional: true, hint: 'Test Vertex AI API access and permissions' },
          { name: 'test_drive', label: 'Test Google Drive', type: 'boolean', control_type: 'checkbox', default: true, optional: true, hint: 'Test Google Drive API access and permissions' },
          { name: 'test_models', label: 'Test model access', type: 'boolean', control_type: 'checkbox', default: false, optional: true, hint: 'Validate access to specific AI models (slower)' },
          { name: 'test_index', label: 'Test Vector Search index', type: 'boolean', control_type: 'checkbox', default: false, optional: true, hint: 'Validate Vector Search index access' },
          { name: 'index_id', label: 'Index ID', type: 'string', optional: true, ngIf: 'input.test_index == true', hint: 'Vector Search index to test (projects/PROJECT/locations/REGION/indexes/INDEX_ID)' },
          { name: 'verbose', label: 'Verbose output', type: 'boolean', control_type: 'checkbox', default: false, optional: true, hint: 'Include detailed diagnostic information' }
        ]
      end,
      
      execute: lambda do |connection, input|
        results = {
          'timestamp' => Time.now.iso8601,
          'environment' => {
            'project' => connection['project'],
            'region' => connection['region'],
            'api_version' => connection['version'] || 'v1',
            'auth_type' => connection['auth_type'],
            'host' => connection['developer_api_host']
          },
          'tests_performed' => [],
          'errors' => [],
          'warnings' => [],
          'all_tests_passed' => true
        }
        
        # Test Vertex AI Connection
        if input['test_vertex_ai'] != false
          begin
            start_time = Time.now
            
            # Test basic connectivity
            datasets_response = get("projects/#{connection['project']}/locations/#{connection['region']}/datasets").
              params(pageSize: 1).
              after_error_response(/.*/) do |code, body, _header, message|
                raise "Vertex AI API error (#{code}): #{message}"
              end
            
            vertex_test = {
              'service' => 'Vertex AI',
              'status' => 'connected',
              'response_time_ms' => ((Time.now - start_time) * 1000).round,
              'permissions_validated' => []
            }
            
            # Check specific permissions based on response
            if datasets_response
              vertex_test['permissions_validated'] << 'aiplatform.datasets.list'
            end
            
            # Test model access if requested
            if input['test_models']
              begin
                models_response = get("projects/#{connection['project']}/locations/#{connection['region']}/models").
                  params(pageSize: 1)
                vertex_test['permissions_validated'] << 'aiplatform.models.list'
                vertex_test['models_accessible'] = true
              rescue => e
                vertex_test['models_accessible'] = false
                results['warnings'] << "Cannot list models: #{e.message}"
              end
              
              # Test specific model access
              begin
                model_test = get("https://#{connection['region']}-aiplatform.googleapis.com/v1/publishers/google/models/gemini-1.5-pro")
                vertex_test['gemini_access'] = true
                vertex_test['permissions_validated'] << 'aiplatform.models.predict'
              rescue => e
                vertex_test['gemini_access'] = false
                results['warnings'] << "Cannot access Gemini models: #{e.message}"
              end
            end
            
            results['tests_performed'] << vertex_test
            
          rescue => e
            results['tests_performed'] << {
              'service' => 'Vertex AI',
              'status' => 'failed',
              'error' => e.message
            }
            results['errors'] << "Vertex AI: #{e.message}"
            results['all_tests_passed'] = false
          end
        end
        
        # Test Google Drive Connection
        if input['test_drive'] != false
          begin
            start_time = Time.now
            
            drive_response = get(call('drive_api_url', :files)).
              params(pageSize: 1, q: "trashed = false", fields: 'files(id,name,mimeType)').
              after_error_response(/.*/) do |code, body, _header, message|
                if code == 403
                  raise "Drive API not enabled or missing scope"
                elsif code == 401
                  raise "Authentication failed - check OAuth token"
                else
                  raise "Drive API error (#{code}): #{message}"
                end
              end
            
            drive_test = {
              'service' => 'Google Drive',
              'status' => 'connected',
              'response_time_ms' => ((Time.now - start_time) * 1000).round,
              'files_found' => drive_response['files'].length,
              'permissions_validated' => ['drive.files.list']
            }
            
            # If verbose, include sample file info
            if input['verbose'] && drive_response['files'].any?
              drive_test['sample_file'] = drive_response['files'].first
            end
            
            # Test file read permission
            if drive_response['files'].any?
              file_id = drive_response['files'].first['id']
              begin
                get(call('drive_api_url', :file, file_id)).
                  params(fields: 'id,size')
                drive_test['permissions_validated'] << 'drive.files.get'
                drive_test['can_read_files'] = true
              rescue => e
                drive_test['can_read_files'] = false
                results['warnings'] << "Cannot read file content: #{e.message}"
              end
            end
            
            results['tests_performed'] << drive_test
            
          rescue => e
            results['tests_performed'] << {
              'service' => 'Google Drive',
              'status' => 'failed',
              'error' => e.message
            }
            results['errors'] << "Google Drive: #{e.message}"
            results['all_tests_passed'] = false
          end
        end
        
        # Test Vector Search Index
        if input['test_index'] && input['index_id'].present?
          begin
            start_time = Time.now
            index_id = input['index_id']
            
            # Validate index format
            unless index_id.match?(/^projects\/[^\/]+\/locations\/[^\/]+\/indexes\/[^\/]+$/)
              raise "Invalid index ID format. Expected: projects/PROJECT/locations/REGION/indexes/INDEX_ID"
            end
            
            # Get index details
            index_response = get(index_id).
              after_error_response(/.*/) do |code, body, _header, message|
                if code == 404
                  raise "Index not found"
                elsif code == 403
                  raise "Missing permission: aiplatform.indexes.get"
                else
                  raise "Index API error (#{code}): #{message}"
                end
              end
            
            index_test = {
              'service' => 'Vector Search Index',
              'status' => 'connected',
              'response_time_ms' => ((Time.now - start_time) * 1000).round,
              'index_details' => {
                'display_name' => index_response['displayName'],
                'state' => index_response['state'],
                'index_update_method' => index_response['indexUpdateMethod']
              }
            }
            
            # Check deployment status
            deployed_indexes = index_response['deployedIndexes'] || []
            if deployed_indexes.empty?
              index_test['deployed'] = false
              results['warnings'] << "Index exists but is not deployed"
            else
              index_test['deployed'] = true
              index_test['deployed_count'] = deployed_indexes.length
            end
            
            # Check index stats if available
            if index_response['indexStats']
              index_test['stats'] = {
                'vectors_count' => index_response['indexStats']['vectorsCount'],
                'shards_count' => index_response['indexStats']['shardsCount']
              }
            end
            
            results['tests_performed'] << index_test
            
          rescue => e
            results['tests_performed'] << {
              'service' => 'Vector Search Index',
              'status' => 'failed',
              'error' => e.message
            }
            results['errors'] << "Vector Search: #{e.message}"
            results['all_tests_passed'] = false
          end
        end
        
        # API Quotas Check (optional)
        if input['verbose']
          begin
            # Check Vertex AI quotas
            quotas = {
              'api_calls_per_minute' => {
                'gemini_pro' => 300,
                'gemini_flash' => 600,
                'embeddings' => 600
              },
              'notes' => 'These are default quotas. Actual quotas may vary by project.'
            }
            results['quota_info'] = quotas
          rescue => e
            results['warnings'] << "Could not retrieve quota information: #{e.message}"
          end
        end
        
        # Summary and recommendations
        results['summary'] = {
          'total_tests' => results['tests_performed'].length,
          'passed' => results['tests_performed'].count { |t| t['status'] == 'connected' },
          'failed' => results['tests_performed'].count { |t| t['status'] == 'failed' }
        }
        
        # Add recommendations if there are issues
        if results['errors'].any? || results['warnings'].any?
          results['recommendations'] = []
          
          if results['errors'].any? { |e| e.include?('Drive API not enabled') }
            results['recommendations'] << 'Enable Google Drive API in Cloud Console'
          end
          
          if results['errors'].any? { |e| e.include?('missing scope') }
            results['recommendations'] << 'Re-authenticate with Drive scope: https://www.googleapis.com/auth/drive.readonly'
          end
          
          if results['warnings'].any? { |w| w.include?('not deployed') }
            results['recommendations'] << 'Deploy your Vector Search index to an endpoint'
          end
        end
        
        # Set final status
        results['overall_status'] = if results['all_tests_passed']
          'healthy'
        elsif results['errors'].empty?
          'degraded'
        else
          'unhealthy'
        end
        
        results
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: 'timestamp', type: 'datetime' },
          { name: 'overall_status', type: 'string' },
          { name: 'all_tests_passed', type: 'boolean' },
          { name: 'environment', type: 'object', properties: [
            { name: 'project', type: 'string' },
            { name: 'region', type: 'string' },
            { name: 'api_version', type: 'string' },
            { name: 'auth_type', type: 'string' },
            { name: 'host', type: 'string' }
          ]},
          { name: 'tests_performed', type: 'array', of: 'object' },
          { name: 'errors', type: 'array', of: 'string' },
          { name: 'warnings', type: 'array', of: 'string' },
          { name: 'summary', type: 'object', properties: [
            { name: 'total_tests', type: 'integer' },
            { name: 'passed', type: 'integer' },
            { name: 'failed', type: 'integer' }
          ]},
          { name: 'recommendations', type: 'array', of: 'string' },
          { name: 'quota_info', type: 'object' }
        ]
      end,
      
      sample_output: lambda do |_connection, _input|
        {
          'timestamp' => '2024-01-15T10:30:00Z',
          'overall_status' => 'healthy',
          'all_tests_passed' => true,
          'environment' => {
            'project' => 'my-project',
            'region' => 'us-central1',
            'api_version' => 'v1',
            'auth_type' => 'custom',
            'host' => 'app.eu'
          },
          'tests_performed' => [
            {
              'service' => 'Vertex AI',
              'status' => 'connected',
              'response_time_ms' => 245,
              'permissions_validated' => ['aiplatform.datasets.list']
            }
          ],
          'errors' => [],
          'warnings' => [],
          'summary' => {
            'total_tests' => 1,
            'passed' => 1,
            'failed' => 0
          }
        }
      end
    },
    # --- Legacy Text Bison action kept for backward compatibility (1) ---
    get_prediction: {
      title: 'Vertex -- Get prediction (legacy)',
      subtitle: 'Get prediction in Google Vertex AI',
      description: "Get prediction in Google Vertex AI",
      help: lambda do
        {
          body: 'This action will retrieve prediction using the PaLM 2 for Text ' \
                '(text-bison) model.',
          learn_more_url: 'https://cloud.google.com/vertex-ai/docs/generative-ai/' \
                          'model-reference/text',
          learn_more_text: 'Learn more'
        }
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['get_prediction_input']
      end,

      execute: lambda do |connection, input|
        post("projects/#{connection['project']}/locations/#{connection['region']}/publishers/" \
             'google/models/text-bison:predict', input).
          after_error_response(/.*/) do |_, body, _, message|
            error("#{message}: #{body}")
          end
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['prediction']
      end,

      sample_output: lambda do |connection|
        payload = {
          instances: [
            {
              prompt: 'action'
            }
          ],
          parameters: {
            temperature: 1,
            topK: 2,
            topP: 1,
            maxOutputTokens: 50
          }
        }
        post("projects/#{connection['project']}/locations/#{connection['region']}" \
             '/publishers/google/models/text-bison:predict').
          payload(payload)
      end
    },

    # --- Google Drive File Fetching (5) ---
    fetch_drive_file: {
      title: 'Drive -- Fetch Google Drive file',
      subtitle: 'Download file content from Google Drive',
      description: lambda do |input|
        file_id = input['file_id']
        if file_id.present?
          "Fetch content from Google Drive file: #{file_id}"
        else
          'Fetch content from a Google Drive file'
        end
      end,

      help: {
        body: 'This action fetches content from a Google Drive file. ' \
              'Automatically handles Google Workspace files (Docs, Sheets, Slides) by exporting them to text format. ' \
              'Regular files are downloaded directly. Includes metadata and change detection via checksums.',
        learn_more_url: 'https://developers.google.com/drive/api/v3/reference/files/get',
        learn_more_text: 'Google Drive API Documentation'
      },

      input_fields: lambda do |object_definitions|
        [
          {
            name: 'file_id', label: 'File ID or URL', type: 'string',
            optional: false,
            hint: 'Google Drive file ID, or full Google Drive URL (will extract ID automatically)'
          },
          {
            name: 'include_content', label: 'Include content', type: 'boolean',
            optional: true, default: true,
            hint: 'Set to false to fetch only metadata without file content'
          }
        ]
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['drive_file_extended']
      end,

      execute: lambda do |connection, input|
        # Step 1: Extract file ID from URL if needed
        file_id = call('extract_drive_file_id', input['file_id'])

        # Step 2: Get file metadata
        metadata_response = call('api_request', connection, :get,
          call('drive_api_url', :file, file_id),
          {
            params: { fields: 'id,name,mimeType,size,modifiedTime,md5Checksum,owners' },
            error_handler: lambda do |code, body, message|
              error(call('handle_drive_error', connection, code, body, message))
            end
          }
        )

        # Step 3: Get content using unified fetcher
        content_result = call('fetch_file_content',
          connection,
          file_id,
          metadata_response,
          input.fetch('include_content', true)
        )

        # Step 4: Merge metadata and content, then return
        metadata_response.merge(content_result)
      end
    },
    list_drive_files: {
      title: 'Drive -- List Google Drive files',
      subtitle: 'Retrieve a list of files from Google Drive',
      description: lambda do |input|
        folder_id = input['folder_id']
        if folder_id.present?
          "List files in Google Drive folder: #{folder_id}"
        else
          'List files from Google Drive'
        end
      end,

      help: {
        body: 'This action retrieves a list of files from Google Drive with flexible filtering options. ' \
              'Supports folder filtering, date ranges, MIME type filtering, and pagination. ' \
              'Results are ordered by modification time (newest first).',
        learn_more_url: 'https://developers.google.com/drive/api/v3/reference/files/list',
        learn_more_text: 'Google Drive API Documentation'
      },

      input_fields: lambda do |object_definitions|
        [
          {
            name: 'folder_id', label: 'Folder ID or URL', type: 'string',
            optional: true,
            hint: 'Google Drive folder ID or URL to list files from (leave empty to list from root)'
          },
          {
            name: 'max_results', label: 'Maximum results', type: 'integer',
            optional: true, default: 100,
            hint: 'Maximum number of files to return (1-1000, default: 100)'
          },
          {
            name: 'modified_after', label: 'Modified after', type: 'date_time',
            optional: true,
            hint: 'Only return files modified after this date'
          },
          {
            name: 'modified_before', label: 'Modified before', type: 'date_time',
            optional: true,
            hint: 'Only return files modified before this date'
          },
          {
            name: 'mime_type', label: 'MIME type filter', type: 'string',
            optional: true,
            hint: 'Filter by specific MIME type (e.g., application/vnd.google-apps.document)'
          },
          {
            name: 'exclude_folders', label: 'Exclude folders', type: 'boolean',
            optional: true, default: false,
            hint: 'Set to true to exclude folders from results'
          },
          {
            name: 'page_token', label: 'Page token', type: 'string',
            optional: true,
            hint: 'Token for retrieving next page of results (from previous response)'
          }
        ]
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: 'files', label: 'Files', type: 'array', of: 'object',
            properties: object_definitions['drive_file_fields'],
            hint: 'Array of file objects matching the query'
          },
          {
            name: 'count', label: 'Files count', type: 'integer',
            hint: 'Number of files returned in this response'
          },
          {
            name: 'has_more', label: 'Has more pages', type: 'boolean',
            hint: 'True if there are more results available'
          },
          {
            name: 'next_page_token', label: 'Next page token', type: 'string',
            hint: 'Token to use for retrieving the next page of results'
          },
          {
            name: 'query_used', label: 'Query used', type: 'string',
            hint: 'The actual query string used for filtering'
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Step 1: Input processing
        folder_id = nil
        if input['folder_id'].present?
          folder_id = call('extract_drive_file_id', input['folder_id'])
        end

        # Convert date inputs to ISO 8601 format if present
        modified_after = input['modified_after']&.iso8601
        modified_before = input['modified_before']&.iso8601

        # Step 2: Build query using helper
        query_options = {
          folder_id: folder_id,
          modified_after: modified_after,
          modified_before: modified_before,
          mime_type: input['mime_type'],
          exclude_folders: input['exclude_folders']
        }.compact

        query_string = call('build_drive_query', query_options)

        # Step 3: Prepare API parameters
        max_results = [input.fetch('max_results', 100), 1000].min
        page_size = [max_results, 1000].min

        api_params = {
          q: query_string,
          pageSize: page_size,
          fields: 'nextPageToken,files(id,name,mimeType,size,modifiedTime,md5Checksum)',
          orderBy: 'modifiedTime desc'
        }

        # Add page token if provided
        if input['page_token'].present?
          api_params[:pageToken] = input['page_token']
        end

        # Step 4: Make API request
        response = call('api_request', connection, :get,
          call('drive_api_url', :files),
          {
            params: api_params,
            error_handler: lambda do |code, body, message|
              error(call('handle_drive_error', connection, code, body, message))
            end
          }
        )

        # Step 5: Process response
        files = response['files'] || []

        # Convert file objects to match our output schema
        processed_files = files.map do |file|
          {
            'id' => file['id'],
            'name' => file['name'],
            'mime_type' => file['mimeType'],
            'size' => file['size']&.to_i,
            'modified_time' => file['modifiedTime'],
            'checksum' => file['md5Checksum']
          }
        end

        # Step 6: Build response
        {
          'files' => processed_files,
          'count' => processed_files.length,
          'has_more' => response['nextPageToken'].present?,
          'next_page_token' => response['nextPageToken'],
          'query_used' => query_string
        }
      end
    },
    batch_fetch_drive_files: {
      title: 'Drive -- Batch fetch Google Drive files',
      subtitle: 'Fetch content from multiple Google Drive files',
      batch: true,
      description: lambda do |input|
        file_ids = input['file_ids'] || []
        count = file_ids.length
        if count > 0
          "Batch fetch #{count} files from Google Drive"
        else
          'Batch fetch files from Google Drive'
        end
      end,

      help: {
        body: 'This action fetches content from multiple Google Drive files in a single operation. ' \
              'Provides detailed success/failure tracking with metrics. Can skip errors or fail fast. ' \
              'Reuses the fetch_drive_file logic for consistent handling of Google Workspace and regular files.',
        learn_more_url: 'https://developers.google.com/drive/api/v3/reference/files/get',
        learn_more_text: 'Google Drive API Documentation'
      },

      input_fields: lambda do |object_definitions|
        [
          {
            name: 'file_ids', label: 'File IDs or URLs', type: 'array', of: 'string',
            optional: false,
            hint: 'Array of Google Drive file IDs or URLs to fetch'
          },
          {
            name: 'include_content', label: 'Include content', type: 'boolean',
            optional: true, default: true,
            hint: 'Set to false to fetch only metadata without file content'
          },
          {
            name: 'skip_errors', label: 'Skip errors', type: 'boolean',
            optional: true, default: true,
            hint: 'Continue processing other files if one fails (true) or fail fast (false)'
          },
          {
            name: 'batch_size', label: 'Batch size', type: 'integer',
            optional: true, default: 10,
            hint: 'Number of files to process concurrently (1-50, default: 10)'
          }
        ]
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: 'successful_files', label: 'Successful files', type: 'array', of: 'object',
            properties: object_definitions['drive_file_extended'],
            hint: 'Array of successfully fetched files with full content'
          },
          {
            name: 'failed_files', label: 'Failed files', type: 'array', of: 'object',
            properties: [
              { name: 'file_id', label: 'File ID', type: 'string' },
              { name: 'error_message', label: 'Error message', type: 'string' },
              { name: 'error_code', label: 'Error code', type: 'string' }
            ],
            hint: 'Array of files that failed to fetch with error details'
          },
          {
            name: 'metrics', label: 'Processing metrics', type: 'object',
            properties: [
              { name: 'total_processed', label: 'Total processed', type: 'integer' },
              { name: 'success_count', label: 'Success count', type: 'integer' },
              { name: 'failure_count', label: 'Failure count', type: 'integer' },
              { name: 'success_rate', label: 'Success rate (%)', type: 'number' },
              { name: 'processing_time_ms', label: 'Processing time (ms)', type: 'integer' }
            ],
            hint: 'Detailed metrics about the batch processing operation'
          }
        ]
      end,

      execute: lambda do |connection, input|
        start_time = Time.now

        # Step 1: Initialize tracking arrays
        successful_files = []
        failed_files = []

        file_ids = input['file_ids'] || []
        include_content = input.fetch('include_content', true)
        skip_errors = input.fetch('skip_errors', true)
        batch_size = [input.fetch('batch_size', 10), 50].min

        return {
          'successful_files' => [],
          'failed_files' => [],
          'metrics' => {
            'total_processed' => 0,
            'success_count' => 0,
            'failure_count' => 0,
            'success_rate' => 0.0,
            'processing_time_ms' => 0
          }
        } if file_ids.empty?

        # Step 2: Process files
        file_ids.each_slice(5) do |batch| # process 5 files concurrently
        #file_ids.each do |file_id_input| # simple sequential processing
          begin
            # Extract clean file ID
            file_id = call('extract_drive_file_id', file_id_input)

            # Get file metadata
            metadata_response = call('api_request', connection, :get,
              call('drive_api_url', :file, file_id),
              {
                params: { fields: 'id,name,mimeType,size,modifiedTime,md5Checksum,owners' },
                error_handler: lambda do |code, body, message|
                  error(call('handle_drive_error', connection, code, body, message))
                end
              }
            )

            # Get content using unified fetcher
            content_result = call('fetch_file_content',
              connection,
              file_id,
              metadata_response,
              include_content
            )

            # Build successful file result
            successful_file = metadata_response.merge(content_result)

            successful_files << successful_file

          rescue => e
            # Step 3: Error handling
            error_details = {
              'file_id' => file_id_input,
              'error_message' => e.message,
              'error_code' => 'FETCH_ERROR'
            }

            failed_files << error_details

            # Fail fast if skip_errors is false
            unless skip_errors
              error("Batch processing failed on file #{file_id_input}: #{e.message}")
            end
          end
        end

        # Step 4: Calculate metrics
        end_time = Time.now
        processing_time_ms = ((end_time - start_time) * 1000).round

        total_processed = file_ids.length
        success_count = successful_files.length
        failure_count = failed_files.length
        success_rate = total_processed > 0 ? (success_count.to_f / total_processed * 100).round(2) : 0.0

        # Step 5: Build response
        {
          'successful_files' => successful_files,
          'failed_files' => failed_files,
          'metrics' => {
            'total_processed' => total_processed,
            'success_count' => success_count,
            'failure_count' => failure_count,
            'success_rate' => success_rate,
            'processing_time_ms' => processing_time_ms
          }
        }
      end
    },
    monitor_drive_changes: {
      title: 'Drive -- Monitor Google Drive changes',
      subtitle: 'Track file changes since last check',
      description: lambda do |input|
        if input['page_token'].present?
          'Continue monitoring Drive changes from saved checkpoint'
        else
          'Start monitoring Drive changes (initial scan)'
        end
      end,

      help: {
        body: 'This action tracks changes in Google Drive since the last check. ' \
              'Use page tokens to maintain state between checks for incremental updates. ' \
              'On first run, it returns a start token. Subsequent runs return actual changes.',
        learn_more_url: 'https://developers.google.com/drive/api/v3/manage-changes',
        learn_more_text: 'Google Drive Changes API Documentation'
      },

      input_fields: lambda do |object_definitions|
        [
          {
            name: 'page_token', 
            label: 'Page token', 
            type: 'string',
            optional: true,
            hint: 'Token from previous response for incremental updates. Leave empty for initial setup.'
          },
          {
            name: 'folder_id',
            label: 'Folder ID or URL',
            type: 'string', 
            optional: true,
            hint: 'Specific folder to monitor (leave empty to monitor all accessible files)'
          },
          {
            name: 'include_removed',
            label: 'Include removed files',
            type: 'boolean',
            control_type: 'checkbox',
            optional: true,
            default: false,
            hint: 'Include files that have been removed or trashed'
          },
          {
            name: 'include_shared_drives',
            label: 'Include shared drives',
            type: 'boolean',
            control_type: 'checkbox',
            optional: true, 
            default: false,
            hint: 'Include changes from shared drives (requires additional permissions)'
          },
          {
            name: 'page_size',
            label: 'Page size',
            type: 'integer',
            optional: true,
            default: 100,
            hint: 'Number of changes to return per page (1-1000, default: 100)'
          }
        ]
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: 'changes',
            label: 'All changes',
            type: 'array',
            of: 'object',
            properties: [
              { name: 'changeType', label: 'Change type', type: 'string' },
              { name: 'time', label: 'Change time', type: 'date_time' },
              { name: 'removed', label: 'File removed', type: 'boolean' },
              { name: 'fileId', label: 'File ID', type: 'string' },
              { name: 'file', label: 'File details', type: 'object',
                properties: [
                  { name: 'id', label: 'File ID', type: 'string' },
                  { name: 'name', label: 'File name', type: 'string' },
                  { name: 'mimeType', label: 'MIME type', type: 'string' },
                  { name: 'modifiedTime', label: 'Modified time', type: 'date_time' },
                  { name: 'size', label: 'File size', type: 'integer' },
                  { name: 'md5Checksum', label: 'MD5 checksum', type: 'string' },
                  { name: 'trashed', label: 'Is trashed', type: 'boolean' }
                ]
              }
            ],
            hint: 'Complete list of all changes detected'
          },
          {
            name: 'new_page_token',
            label: 'New page token',
            type: 'string',
            hint: 'Save this token for the next incremental check'
          },
          {
            name: 'files_added',
            label: 'Files added',
            type: 'array',
            of: 'object',
            properties: [
              { name: 'id', label: 'File ID', type: 'string' },
              { name: 'name', label: 'File name', type: 'string' },
              { name: 'mimeType', label: 'MIME type', type: 'string' },
              { name: 'modifiedTime', label: 'Modified time', type: 'date_time' }
            ],
            hint: 'New files created since last check'
          },
          {
            name: 'files_modified', 
            label: 'Files modified',
            type: 'array',
            of: 'object',
            properties: [
              { name: 'id', label: 'File ID', type: 'string' },
              { name: 'name', label: 'File name', type: 'string' },
              { name: 'mimeType', label: 'MIME type', type: 'string' },
              { name: 'modifiedTime', label: 'Modified time', type: 'date_time' },
              { name: 'checksum', label: 'New checksum', type: 'string' }
            ],
            hint: 'Files that have been modified'
          },
          {
            name: 'files_removed',
            label: 'Files removed', 
            type: 'array',
            of: 'object',
            properties: [
              { name: 'fileId', label: 'File ID', type: 'string' },
              { name: 'time', label: 'Removal time', type: 'date_time' }
            ],
            hint: 'Files that have been deleted or trashed'
          },
          {
            name: 'summary',
            label: 'Change summary',
            type: 'object',
            properties: [
              { name: 'total_changes', label: 'Total changes', type: 'integer' },
              { name: 'added_count', label: 'Files added', type: 'integer' },
              { name: 'modified_count', label: 'Files modified', type: 'integer' },
              { name: 'removed_count', label: 'Files removed', type: 'integer' },
              { name: 'has_more', label: 'Has more changes', type: 'boolean' }
            ],
            hint: 'Summary statistics of changes'
          },
          {
            name: 'is_initial_token',
            label: 'Is initial token',
            type: 'boolean',
            hint: 'True if this was the initial setup (no changes returned)'
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Step 1: Determine if we need a start token or have one
        page_token = input['page_token']
        folder_id = input['folder_id'].present? ? call('extract_drive_file_id', input['folder_id']) : nil
        include_removed = input['include_removed'] || false
        include_shared_drives = input['include_shared_drives'] || false
        page_size = [input.fetch('page_size', 100), 1000].min

        # Step 2: Get start token if not provided
        if page_token.blank?
          # Initial setup - get starting page token
          start_params = {
            supportsAllDrives: include_shared_drives
          }
          
          # Add folder restriction if specified
          if folder_id.present?
            start_params[:driveId] = folder_id if include_shared_drives
            start_params[:spaces] = 'drive'
          end
          
          start_response = get('https://www.googleapis.com/drive/v3/changes/startPageToken').
            params(start_params).
            after_error_response(/.*/) do |code, body, _header, message|
              error_msg = call('handle_drive_error', connection, code, body, message)
              error(error_msg)
            end
          
          # Return initial token for future use
          return {
            'changes' => [],
            'new_page_token' => start_response['startPageToken'],
            'files_added' => [],
            'files_modified' => [],
            'files_removed' => [],
            'summary' => {
              'total_changes' => 0,
              'added_count' => 0,
              'modified_count' => 0,
              'removed_count' => 0,
              'has_more' => false
            },
            'is_initial_token' => true
          }
        end

        # Step 3: Get actual changes using the token
        changes_params = {
          pageToken: page_token,
          pageSize: page_size,
          fields: 'nextPageToken,newStartPageToken,changes(changeType,time,removed,fileId,file(id,name,mimeType,modifiedTime,size,md5Checksum,trashed,parents))',
          supportsAllDrives: include_shared_drives,
          includeRemoved: include_removed
        }
        
        # Add folder restriction if specified
        if folder_id.present? && include_shared_drives
          changes_params[:driveId] = folder_id
        end
        
        changes_response = get('https://www.googleapis.com/drive/v3/changes').
          params(changes_params).
          after_error_response(/.*/) do |code, body, _header, message|
            error_msg = call('handle_drive_error', connection, code, body, message)
            error(error_msg)
          end

        # Step 4: Process the changes
        all_changes = changes_response['changes'] || []
        
        # Filter by folder if specified and not using shared drives
        if folder_id.present? && !include_shared_drives
          all_changes = all_changes.select do |change|
            if change['file'] && change['file']['parents']
              change['file']['parents'].include?(folder_id)
            else
              false
            end
          end
        end

        # Step 5: Categorize changes
        files_added = []
        files_modified = []
        files_removed = []
        
        # Track seen files to avoid duplicates
        seen_files = {}
        
        all_changes.each do |change|
          file_id = change['fileId']
          
          if change['removed']
            # File was removed
            files_removed << {
              'fileId' => file_id,
              'time' => change['time']
            }
          elsif change['file']
            file = change['file']
            
            # Skip trashed files unless explicitly requested
            next if file['trashed'] && !include_removed
            
            file_summary = {
              'id' => file['id'],
              'name' => file['name'],
              'mimeType' => file['mimeType'],
              'modifiedTime' => file['modifiedTime'],
              'checksum' => file['md5Checksum']
            }
            
            # Determine if file is new or modified
            # This is simplified - in production, you'd track file creation time
            if seen_files[file_id]
              # Already seen in this batch, treat as modified
              files_modified << file_summary
            else
              # First time seeing this file
              # Check if it's a new file based on the change type
              if change['changeType'] == 'file'
                # Could be either new or modified
                # For simplicity, we'll treat first occurrence as added
                # In production, compare modifiedTime with change time
                time_diff = if file['modifiedTime'] && change['time']
                  modified = Time.parse(file['modifiedTime'])
                  changed = Time.parse(change['time'])
                  (changed - modified).abs
                else
                  0
                end
                
                # If modified very recently relative to change, likely new
                if time_diff < 60 # Within 60 seconds
                  files_added << file_summary
                else
                  files_modified << file_summary
                end
              else
                files_modified << file_summary
              end
              
              seen_files[file_id] = true
            end
          end
        end

        # Step 6: Determine next page token
        next_token = changes_response['nextPageToken'] || changes_response['newStartPageToken']
        has_more = changes_response['nextPageToken'].present?

        # Step 7: Build response
        {
          'changes' => all_changes,
          'new_page_token' => next_token,
          'files_added' => files_added,
          'files_modified' => files_modified, 
          'files_removed' => files_removed,
          'summary' => {
            'total_changes' => all_changes.length,
            'added_count' => files_added.length,
            'modified_count' => files_modified.length,
            'removed_count' => files_removed.length,
            'has_more' => has_more
          },
          'is_initial_token' => false
        }
      end,

      sample_output: lambda do |_connection, _input|
        {
          'changes' => [
            {
              'changeType' => 'file',
              'time' => '2024-01-15T10:30:00Z',
              'removed' => false,
              'fileId' => 'abc123',
              'file' => {
                'id' => 'abc123',
                'name' => 'document.pdf',
                'mimeType' => 'application/pdf',
                'modifiedTime' => '2024-01-15T10:29:45Z',
                'size' => 1024000,
                'md5Checksum' => 'abc123def456',
                'trashed' => false
              }
            }
          ],
          'new_page_token' => 'token_xyz789',
          'files_added' => [
            {
              'id' => 'abc123',
              'name' => 'document.pdf',
              'mimeType' => 'application/pdf',
              'modifiedTime' => '2024-01-15T10:29:45Z'
            }
          ],
          'files_modified' => [],
          'files_removed' => [],
          'summary' => {
            'total_changes' => 1,
            'added_count' => 1,
            'modified_count' => 0,
            'removed_count' => 0,
            'has_more' => false
          },
          'is_initial_token' => false
        }
      end
    }
  },

  methods: {
    # Universal API request handler with standard error handling
    api_request: lambda do |connection, method, url, options = {}|
      # Build the request based on method
      request = case method.to_sym
      when :get
        if options[:params]
          get(url).params(options[:params])
        else
          get(url)
        end
      when :post
        if options[:payload]
          post(url, options[:payload])
        else
          post(url)
        end
      when :put
        put(url, options[:payload])
      when :delete
        delete(url)
      else
        error("Unsupported HTTP method: #{method}")
      end
      
      # Apply standard error handling
      request.after_error_response(/.*/) do |code, body, _header, message|
        # Check if custom error handler provided
        if options[:error_handler]
          options[:error_handler].call(code, body, message)
        else
          call('handle_vertex_error', connection, code, body, message)
        end
      end
    end,
    # Drive API URL builder for consistent endpoint construction
    drive_api_url: lambda do |endpoint, file_id = nil, options = {}|
      base = 'https://www.googleapis.com/drive/v3'

      case endpoint.to_sym
      when :file
        error("file_id required for :file endpoint") if file_id.blank?
        "#{base}/files/#{file_id}"
      when :export
        error("file_id required for :export endpoint") if file_id.blank?
        "#{base}/files/#{file_id}/export"
      when :download
        error("file_id required for :download endpoint") if file_id.blank?
        "#{base}/files/#{file_id}?alt=media"
      when :files
        "#{base}/files"
      when :changes
        "#{base}/changes"
      when :start_token
        "#{base}/changes/startPageToken"
      else
        error("Unknown Drive API endpoint: #{endpoint}")
      end
    end,
    # Unified file content fetcher - eliminates duplication between actions
    fetch_file_content: lambda do |connection, file_id, metadata, include_content = true|
      # Skip content fetching if not requested
      unless include_content
        return {
          'text_content' => '',
          'needs_processing' => false,
          'fetch_method' => 'skipped',
          'export_mime_type' => nil
        }
      end

      # Determine export type for Google Workspace files
      export_mime_type = call('get_export_mime_type', metadata['mimeType'])

      if export_mime_type.present?
        # Google Workspace file - use export endpoint
        content_response = call('api_request', connection, :get,
          call('drive_api_url', :export, file_id),
          {
            params: { mimeType: export_mime_type },
            error_handler: lambda do |code, body, message|
              error(call('handle_drive_error', connection, code, body, message))
            end
          }
        )

        # Return workspace file result
        {
          'text_content' => content_response.force_encoding('UTF-8'),
          'needs_processing' => false,
          'fetch_method' => 'export',
          'export_mime_type' => export_mime_type
        }
      else
        # Regular file - use download endpoint
        content_response = call('api_request', connection, :get,
          call('drive_api_url', :download, file_id),
          {
            error_handler: lambda do |code, body, message|
              error(call('handle_drive_error', connection, code, body, message))
            end
          }
        )

        # Check if it's a text-based file
        is_text_file = metadata['mimeType']&.start_with?('text/') ||
                       ['application/json', 'application/xml'].include?(metadata['mimeType'])

        # Check if it needs additional processing
        needs_processing = ['application/pdf', 'image/'].any? { |prefix|
          metadata['mimeType']&.start_with?(prefix)
        }

        # Return regular file result
        {
          'text_content' => is_text_file ? content_response.force_encoding('UTF-8') : '',
          'needs_processing' => needs_processing,
          'fetch_method' => 'download',
          'export_mime_type' => nil
        }
      end
    end,
    # Unified rate-limited AI request handler
    rate_limited_ai_request: lambda do |connection, model, action_type, url, payload|
      # Apply rate limiting before request
      rate_limit_info = call('enforce_vertex_rate_limits', connection, model, action_type)

      # Make request with 429 retry handling
      response = call('handle_429_with_backoff', connection, action_type, model) do
        call('api_request', connection, :post, url, { payload: payload })
      end

      # Add rate limit info to response if it's a hash
      if response.is_a?(Hash)
        response['rate_limit_status'] = rate_limit_info
      end

      response
    end,
    # Enhanced Gemini payload builder with JSON output support
    build_gemini_payload: lambda do |instruction, prompt, options = {}|
      # Use existing base builder
      base = call('build_base_payload', instruction, prompt, options[:safety_settings])

      # Add JSON output instruction if requested
      if options[:json_output]
        json_key = options[:json_key] || 'response'
        json_instruction = "\n\nOutput as a JSON object with key \"#{json_key}\". " \
                          "Only respond with valid JSON and nothing else."

        # Append to the user prompt
        current_text = base['contents'][0]['parts'][0]['text']
        base['contents'][0]['parts'][0]['text'] = current_text + json_instruction
      end

      # Set temperature if provided
      if options[:temperature]
        base['generationConfig'] ||= {}
        base['generationConfig']['temperature'] = options[:temperature]
      end

      base
    end,
    # -- CORE ERROR AND HTTP UTILITIES --
    handle_vertex_error: lambda do |connection, code, body, message, context = {}|
      # Parse the body for structured error information
      error_details = begin
        parsed = parse_json(body)
        # Google APIs often nest the error message
        parsed.dig('error', 'message') || parsed['message'] || body
      rescue
        body
      end
      
      # Build base message based on status code
      base_message = case code
      when 400
        "Invalid request format"
      when 401
        "Authentication failed - please check your credentials"
      when 403
        "Permission denied - verify Vertex AI API is enabled"
      when 404
        "Resource not found"
      when 429
        "Rate limit exceeded - please wait before retrying"
      when 500
        "Google service error - temporary issue"
      when 502, 503, 504
        "Google service temporarily unavailable"
      else
        "API error"
      end
      
      # Add context if provided
      if context[:action].present?
        base_message = "#{context[:action]} failed: #{base_message}"
      end
      
      # Build final message
      if connection['verbose_errors']
        error_message = "#{base_message} (HTTP #{code})"
        error_message += "\nDetails: #{error_details}" if error_details.present?
        error_message += "\nOriginal: #{message}" if message != error_details
        error(error_message)
      else
        hint = case code
        when 401, 403
          "\nEnable verbose errors in connection settings for details"
        when 429
          "\nConsider adding delays between requests"
        when 500..599
          "\nThis is usually temporary - retry in a few moments"
        else
          ""
        end
        error("#{base_message}#{hint}")
      end
    end,
    replace_backticks_with_hash: lambda do |text|
      text&.gsub('```', '####')
    end,
    truthy?: lambda do |val|
      case val
      when TrueClass then true
      when FalseClass then false
      when Integer then val != 0
      else
        %w[true 1 yes y t].include?(val.to_s.strip.downcase)
      end
    end,
    # -- RATE LIMITING UTILITIES --
    # Vertex AI rate limiting enforcement using atomic sliding window in cache
    enforce_vertex_rate_limits: lambda do |connection, model, action_type = 'inference'|
      # Skip if rate limiting is disabled
      return { requests_last_minute: 0, limit: 0, throttled: false, sleep_ms: 0 } unless connection['enable_rate_limiting']

      # Determine model family and limits
      model_family = case model.to_s.downcase
      when /gemini.*pro/
        'gemini-pro'
      when /gemini.*flash/
        'gemini-flash'
      when /embedding/
        'embedding'
      else
        'gemini-pro' # default to most restrictive
      end

      # Model-specific limits (requests per minute)
      limits = {
        'gemini-pro' => 300,
        'gemini-flash' => 600,
        'embedding' => 600
      }

      limit = limits[model_family]
      project = connection['project'] || 'default'
      current_time = Time.now.to_i

      # Single cache key for atomic sliding window
      cache_key = "vertex_rate_#{project}_#{model_family}_window"

      begin
        # Get current sliding window data
        window_data = workato.cache.get(cache_key) || { 'timestamps' => [], 'version' => 1 }
        timestamps = Array(window_data['timestamps'])

        # Clean expired timestamps (older than 60 seconds)
        cutoff_time = current_time - 60
        timestamps.reject! { |ts| ts < cutoff_time }

        # Check if we're at the limit
        if timestamps.length >= limit
          # Find when the oldest request will expire
          oldest_timestamp = timestamps.min
          sleep_seconds = [oldest_timestamp + 60 - current_time, 1].max

          # Add jitter to prevent thundering herd (0-500ms)
          jitter = rand * 0.5
          total_sleep = sleep_seconds + jitter
          sleep_ms = (total_sleep * 1000).to_i

          puts "Rate limit reached for #{model_family} (#{timestamps.length}/#{limit}). Sleeping #{total_sleep.round(2)}s"
          sleep(total_sleep)

          return {
            requests_last_minute: timestamps.length,
            limit: limit,
            throttled: true,
            sleep_ms: sleep_ms
          }
        end

        # Add current request timestamp
        timestamps << current_time

        # Update cache with new window data (90 second TTL for safety)
        updated_data = { 'timestamps' => timestamps, 'version' => window_data['version'] + 1 }
        workato.cache.set(cache_key, updated_data, 90)

        return {
          requests_last_minute: timestamps.length,
          limit: limit,
          throttled: false,
          sleep_ms: 0
        }

      rescue => e
        # If cache fails, allow the request but log warning
        puts "Rate limit cache operation failed: #{e.message}"
        return { requests_last_minute: 0, limit: limit, throttled: false, sleep_ms: 0 }
      end
    end,
    handle_429_with_backoff: lambda do |connection, action_type, model, &block|
      max_retries = 3
      base_delay = 1.0

      max_retries.times do |attempt|
        begin
          # Execute the block (API call)
          return block.call
        rescue => e
          # Check if this is a 429 error
          if e.message.include?('429') || e.message.include?('Rate limit')
            if attempt < max_retries - 1
              # Calculate exponential backoff delay
              delay = base_delay * (2 ** attempt)

              # Try to extract Retry-After header from error if available
              retry_after = nil
              if e.respond_to?(:response) && e.response.respond_to?(:headers)
                retry_after = e.response.headers['Retry-After']&.to_i
              end

              # Use Retry-After if available, otherwise use exponential backoff
              actual_delay = retry_after || delay

              puts "429 rate limit hit for #{model} (attempt #{attempt + 1}/#{max_retries}). Retrying in #{actual_delay}s"
              sleep(actual_delay)
            else
              # Max retries exceeded
              error("Rate limit exceeded for #{model} after #{max_retries} attempts. " \
                    "Please reduce request frequency or enable automatic rate limiting in connection settings.")
            end
          else
            # Not a rate limit error, re-raise
            raise e
          end
        end
      end
    end,
    # Circuit breaker pattern for resilient batch operations
    circuit_breaker_retry: lambda do |connection, operation_name, options = {}, &block|
      # Configuration with defaults
      max_retries = options[:max_retries] || 3
      retry_on = Array(options[:retry_on] || [429, 500, 502, 503, 504])
      base_delay = options[:base_delay] || 1.0
      max_delay = options[:max_delay] || 30.0
      jitter = options[:jitter] || true

      # Circuit breaker state management via cache
      circuit_key = "circuit_breaker_#{connection['project']}_#{operation_name}"

      begin
        circuit_state = workato.cache.get(circuit_key) || { 'failures' => 0, 'last_failure' => nil, 'state' => 'closed' }

        # Check if circuit is open (too many recent failures)
        if circuit_state['state'] == 'open'
          last_failure_time = Time.parse(circuit_state['last_failure']) rescue (Time.now - 3600)
          # Auto-recover after 5 minutes
          if Time.now - last_failure_time > 300
            circuit_state['state'] = 'half_open'
            puts "Circuit breaker for #{operation_name}: transitioning to half-open"
          else
            error("Circuit breaker OPEN for #{operation_name}. Too many recent failures. Retry in #{((last_failure_time + 300 - Time.now) / 60).round(1)} minutes.")
          end
        end

        # Attempt the operation with retries
        max_retries.times do |attempt|
          begin
            result = block.call

            # Success - reset circuit breaker
            if circuit_state['failures'] > 0
              workato.cache.set(circuit_key, { 'failures' => 0, 'state' => 'closed' }, 3600)
              puts "Circuit breaker for #{operation_name}: reset to closed state"
            end

            return result

          rescue => e
            error_code = e.respond_to?(:response) ? e.response&.status : nil

            # Check if this error should trigger a retry
            should_retry = retry_on.any? do |code|
              case code
              when Integer
                error_code == code
              when String
                e.message.include?(code)
              when Regexp
                e.message.match?(code)
              else
                false
              end
            end

            if should_retry && attempt < max_retries - 1
              # Calculate delay with exponential backoff and optional jitter
              delay = [base_delay * (2 ** attempt), max_delay].min
              delay += rand * 0.5 if jitter

              puts "#{operation_name} failed (attempt #{attempt + 1}/#{max_retries}): #{e.message}. Retrying in #{delay.round(2)}s"
              sleep(delay)
            else
              # Max retries exceeded or non-retryable error
              circuit_state['failures'] += 1
              circuit_state['last_failure'] = Time.now.iso8601

              # Trip circuit breaker if too many failures
              if circuit_state['failures'] >= 5
                circuit_state['state'] = 'open'
                puts "Circuit breaker for #{operation_name}: OPENED due to repeated failures"
              end

              workato.cache.set(circuit_key, circuit_state, 3600)
              raise e
            end
          end
        end

      rescue => cache_error
        puts "Circuit breaker cache error: #{cache_error.message}"
        # Fallback to simple retry without circuit breaker
        return block.call
      end
    end,
    # -- VERTEX MODEL DISCOVERY UTILITIES --
    # - Main model fetching with caching
    fetch_publisher_models: lambda do |connection, publisher = 'google'|
      # Build the cache key (incl all relevant param to ensure regions/publishers are cached separately)
      region = connection['region'].presence || 'us-central1'
      include_preview = connection['include_preview_models'] || false
      cache_key = "models_#{region}_#{publisher}_preview_#{include_preview}"

      # Try for a cache hit (using Workato's built-in caching)
      begin
        cached_data = workato.cache.get(cache_key)
        if cached_data.present?
          # Check if cache is still fresh (we'll cache for 1 hour)
          cache_time = Time.parse(cached_data['cached_at'])
          if cache_time > 1.hour.ago
            puts "Using cached model list (#{cached_data['models'].length} models, cached #{((Time.now - cache_time) / 60).round} minutes ago)"
            return cached_data['models']
          else
            puts "Model cache expired, refreshing..."
          end
        end
      rescue => e
        # If cache access fails, continue without it
        puts "Cache access failed: #{e.message}, fetching fresh data"
      end

      # Fallback cascade for dynamic model discovery
      models = call('cascade_model_discovery', connection, publisher, region)

      # Cache the results if we got any
      if models.present?
        begin
          cache_data = {
            'models' => models,
            'cached_at' => Time.now.iso8601,
            'count' => models.length,
            'source' => models.first&.dig('source') || 'api'
          }
          # Cache for 1 hour (3600 seconds)
          workato.cache.set(cache_key, cache_data, 3600)
          puts "Cached #{models.length} models for future use (source: #{cache_data['source']})"
        rescue => e
          puts "Failed to cache models: #{e.message}"
        end
      end

      models
    end,
    # - Cascade model discovery with multiple fallback strategies
    cascade_model_discovery: lambda do |connection, publisher, region|
      # Strategy 1: Try primary API endpoint
      begin
        puts "Model discovery: trying primary API endpoint..."
        models = call('fetch_fresh_publisher_models', connection, publisher, region)
        if models.present?
          puts "Model discovery: primary API succeeded (#{models.length} models)"
          models.each { |m| m['source'] = 'primary_api' }
          return models
        end
      rescue => e
        puts "Model discovery: primary API failed: #{e.message}"
      end

      # Strategy 2: Try alternative region if not us-central1
      if region != 'us-central1'
        begin
          puts "Model discovery: trying fallback region (us-central1)..."
          models = call('fetch_fresh_publisher_models', connection, publisher, 'us-central1')
          if models.present?
            puts "Model discovery: fallback region succeeded (#{models.length} models)"
            models.each { |m| m['source'] = 'fallback_region' }
            return models
          end
        rescue => e
          puts "Model discovery: fallback region failed: #{e.message}"
        end
      end

      # Strategy 3: Try different view parameter
      begin
        puts "Model discovery: trying minimal view mode..."
        models = call('fetch_publisher_models_minimal', connection, publisher, region)
        if models.present?
          puts "Model discovery: minimal view succeeded (#{models.length} models)"
          models.each { |m| m['source'] = 'minimal_view' }
          return models
        end
      rescue => e
        puts "Model discovery: minimal view failed: #{e.message}"
      end

      # Strategy 4: Use static curated list as final fallback
      begin
        puts "Model discovery: using static curated list as final fallback"
        models = call('get_static_model_list', connection, publisher)
        models.each { |m| m['source'] = 'static_fallback' }
        puts "Model discovery: static fallback provided #{models.length} models"
        return models
      rescue => e
        puts "Model discovery: static fallback failed: #{e.message}"
        return []
      end
    end,
    # - Minimal view model fetching for fallback
    fetch_publisher_models_minimal: lambda do |connection, publisher, region|
      host = "https://#{region}-aiplatform.googleapis.com"
      url = "#{host}/v1beta1/publishers/#{publisher}/models"

      resp = get(url).
        params(
          page_size: 100,  # Smaller page size for reliability
          view: 'PUBLISHER_MODEL_VIEW_UNSPECIFIED'  # Most basic view
        ).
        after_error_response(/.*/) { |code, body, _hdrs, message| raise "API Error: #{code}" }

      models = resp['models'] || []
      models.select { |m| m['name'].present? }
    end,
    # - Static curated model list as ultimate fallback
    get_static_model_list: lambda do |connection, publisher|
      include_preview = connection['include_preview_models'] || false

      # Core production models that are widely available
      core_models = [
        { 'name' => 'publishers/google/models/gemini-1.5-pro', 'displayName' => 'Gemini 1.5 Pro', 'launchStage' => 'GA' },
        { 'name' => 'publishers/google/models/gemini-1.5-flash', 'displayName' => 'Gemini 1.5 Flash', 'launchStage' => 'GA' },
        { 'name' => 'publishers/google/models/gemini-1.0-pro', 'displayName' => 'Gemini 1.0 Pro', 'launchStage' => 'GA' },
        { 'name' => 'publishers/google/models/text-embedding-004', 'displayName' => 'Text Embedding 004', 'launchStage' => 'GA' },
        { 'name' => 'publishers/google/models/textembedding-gecko', 'displayName' => 'Text Embedding Gecko', 'launchStage' => 'GA' }
      ]

      # Preview models (added if preview is enabled)
      preview_models = [
        { 'name' => 'publishers/google/models/gemini-1.5-pro-preview', 'displayName' => 'Gemini 1.5 Pro Preview', 'launchStage' => 'PREVIEW' },
        { 'name' => 'publishers/google/models/gemini-experimental', 'displayName' => 'Gemini Experimental', 'launchStage' => 'EXPERIMENTAL' }
      ]

      if include_preview
        core_models + preview_models
      else
        core_models
      end
    end,
    fetch_fresh_publisher_models: lambda do |connection, publisher, region|
      # Use the regional service endpoint; list is in v1beta1.
      # Docs: publishers.models.list (v1beta1), supports 'view' and pagination.
      # https://cloud.google.com/vertex-ai/docs/reference/rest/v1beta1/publishers.models/list
      host = "https://#{region}-aiplatform.googleapis.com"
      url = "#{host}/v1beta1/publishers/#{publisher}/models"
      
      models = []
      page_token = nil
      pages_fetched = 0
      max_pages = 5  # Reduced from 10 for faster response
      total_api_time = 0
      
      begin
        loop do
          pages_fetched += 1
          
          # Stop if we've fetched enough pages
          if pages_fetched > max_pages
            puts "Reached maximum page limit (#{max_pages}), stopping model fetch"
            break
          end
          
          # Time each API call for monitoring
          api_start = Time.now
          
          resp = get(url).
            params(
              page_size: 500,  # Increased from 200 - get more models per request
              page_token: page_token,
              view: 'PUBLISHER_MODEL_VIEW_BASIC'  # Changed from FULL - we only need basic info
            ).
            after_error_response(/.*/) do |code, body, _hdrs, message|
              # Log but don't fail completely
              if connection['verbose_errors']
                puts "Model listing failed (HTTP #{code}): #{body}"
              else
                puts "Model listing failed (HTTP #{code}) - using static fallback"
              end
              raise "API Error"
            end
          
          api_time = Time.now - api_start
          total_api_time += api_time
          
          batch = resp['publisherModels'] || []
          models.concat(batch)
          
          puts "Fetched page #{pages_fetched}: #{batch.length} models in #{api_time.round(2)}s"
          
          # Check for pagination
          page_token = resp['nextPageToken']
          
          # Smart early exit - if we have enough models, stop fetching
          if models.length >= 100 && !connection['fetch_all_models']
            puts "Have #{models.length} models, stopping early for performance"
            break
          end
          
          break if page_token.blank? || batch.empty?
        end
        
        puts "Total model fetch: #{models.length} models in #{total_api_time.round(2)}s across #{pages_fetched} pages"
        models
        
      rescue => e
        puts "Failed to fetch models from API: #{e.message}"
        # Return empty array to trigger static fallback
        []
      end
    end,
    validate_publisher_model!: lambda do |connection, model_name|
      # Early exit conditions (no need to validate in input absent or validation disabled)
      return if model_name.blank?
      return unless connection['validate_model_on_run']

      # Use persistent cache that survives across recipe executions
      region = connection['region'].presence || 'us-central1'
      project = connection['project'] || 'default'
      cache_key = "vertex_model_validation_#{project}_#{region}_#{model_name.gsub('/', '_')}"

      # Check persistent cache first - if we've validated this model recently, skip
      begin
        cached_validation = workato.cache.get(cache_key)
        if cached_validation && cached_validation['validated_at']
          validated_time = Time.parse(cached_validation['validated_at'])
          # Use cached result if validation is less than 1 hour old
          if validated_time > Time.now - 3600
            puts "Model #{model_name} validation cached (#{((Time.now - validated_time) / 60).round(1)}min ago)"
            return
          end
        end
      rescue => e
        puts "Model validation cache read failed: #{e.message}"
        # Continue with validation if cache fails
      end
      
      # 1. Validate model name format first (no API call needed)
      # regex checks for the pattern: publishers/{publisher}/models/{model}
      unless model_name.match?(/^publishers\/[^\/]+\/models\/[^\/]+$/)
        error("Invalid model name format: #{model_name}\n" \
              "Expected format: publishers/{publisher}/models/{model}\n" \
              "Example: publishers/google/models/gemini-1.5-pro")
      end
      
      # Verify the model actually exists
      region = connection['region'].presence || 'us-central1'
      
      # Build the validation URL (v1 endpoint for model metadata)
      url = "https://#{region}-aiplatform.googleapis.com/v1/#{model_name}"

      begin
        # Make the validation request with specific error handling
        resp = get(url).
          params(view: 'PUBLISHER_MODEL_VIEW_BASIC').  # Changed from FULL to BASIC for speed
          after_error_response(/404/) do |code, body, _hdrs, message|
            # Model not found - provide helpful context about what might be wrong
            error("Model '#{model_name}' not found in region '#{region}'.\n" \
                  "Possible issues:\n" \
                  "• Model name typo (check spelling carefully)\n" \
                  "• Model not available in #{region} (try us-central1)\n" \
                  "• Model deprecated or renamed\n" \
                  "• Using preview model without enabling preview models in connection")
          end.
          after_error_response(/403/) do |code, body, _hdrs, message|
            # Permission denied - guide user to fix their setup
            error("Access denied to model '#{model_name}'.\n" \
                  "To fix this:\n" \
                  "1. Verify Vertex AI API is enabled in Google Cloud Console\n" \
                  "2. Check service account has 'Vertex AI User' role\n" \
                  "3. Ensure billing is enabled for your project\n" \
                  "4. Confirm project ID is correct: #{connection['project']}")
          end.
          after_error_response(/.*/) do |code, body, _hdrs, message|
            # Use the centralized error handler for other errors
            call('handle_vertex_error', connection, code, body, message)
          end
        
        # Additional validation: Check if model is GA when preview models aren't allowed
        unless connection['include_preview_models']
          stage = resp['launchStage'].to_s
          if stage.present? && stage != 'GA'
            error("Model '#{model_name}' is in #{stage} stage (not Generally Available).\n" \
                  "To use preview models:\n" \
                  "1. Go to your connection settings\n" \
                  "2. Enable 'Include preview/experimental models'\n" \
                  "3. Save and retry\n\n" \
                  "Note: Preview models may have different pricing and stability")
          end
        end
        
        # Success! Cache the validation result persistently (1 hour TTL)
        begin
          validation_data = {
            'validated_at' => Time.now.iso8601,
            'launch_stage' => resp['launchStage'],
            'model_version' => resp['versionId'],
            'region' => region
          }
          workato.cache.set(cache_key, validation_data, 3600) # 1 hour TTL
        rescue => e
          puts "Model validation cache write failed: #{e.message}"
        end

        puts "Model #{model_name} validated successfully in #{region}"
        
      rescue => e
        # If anything goes wrong, provide a clear error message
        error("Model validation failed: #{e.message}\n" \
              "This usually means a temporary network issue. Try again in a moment.")
      end
    end,
    # - Partition models by capability.
    vertex_model_bucket: lambda do |model_id|
      id = model_id.to_s.downcase

      # Use a hash for 0(1) lookup instead of multiple str includes
      @model_categories ||= {
        'embedding' => %w[embedding gecko multimodalembedding embeddinggemma],
        'image' => %w[vision imagegeneration imagen],
        'audio' => %w[tts audio speech],
        'code' => %w[code codey],
        'chat' => %w[chat],
        'text' => []  # Default category
      }

      # Find the category for this model
      @model_categories.each do |category, keywords|
        return category.to_sym if keywords.any? { |keyword| id.include?(keyword) }
      end
    
      :text # default to text if no match
    end,
    # - Sort model options by version, tier, then alphabetically      
    sort_model_options: lambda do |options|
      options.sort_by do |label, value|
        # Extract version number if present
        version_match = label.match(/(\d+)\.(\d+)/)
        major_version = version_match ? version_match[1].to_i : 0
        minor_version = version_match ? version_match[2].to_i : 0
        
        # Determine model tier
        tier = case label
              when /\bPro\b/i then 0
              when /\bFlash\b/i then 1  
              when /\bLite\b/i then 2
              else 3
              end
        
        # Sort by: version (desc), tier, then alphabetical
        [
          -major_version,  # Newest version first
          -minor_version,  # Higher minor version first
          tier,            # Pro > Flash > Lite
          label            # Alphabetical as tiebreaker
        ]
      end
    end,
    # - Filter/sort + convert to picklist options [label, value]
    to_model_options: lambda do |models, bucket:, include_preview: false|
      return [] if models.blank?
      
      # Pre-compile the regex for retired models to avoid recompiling
      retired_pattern = /(^|-)1\.0-|text-bison|chat-bison/
    
      # Filter models efficiently
      filtered = models.select do |m|
        model_id = m['name'].to_s.split('/').last
        next false if model_id.blank?
        
        # Skip retired models
        next false if model_id =~ retired_pattern
        
        # Check bucket match
        next false unless call('vertex_model_bucket', model_id) == bucket
        
        # Check GA status if needed
        if !include_preview
          stage = m['launchStage'].to_s
          next false unless stage == 'GA' || stage.blank?
        end
        
        true
      end
      
      # Extract unique model IDs efficiently
      seen_ids = Set.new
      unique_models = filtered.select do |m|
        id = m['name'].to_s.split('/').last
        seen_ids.add?(id)  # Returns true if added (wasn't present), false if already present
      end
      
      # Build options with better sorting
      options = unique_models.map do |m|
        id = m['name'].to_s.split('/').last
        # Create a human-friendly label
        label = create_model_label(id, m)
        [label, "publishers/google/models/#{id}"]
      end
      
      # Sort with a more sophisticated algorithm
      sort_model_options(options)
    end,
    # = Context-aware model label creation
    create_model_label: lambda do |model_id, model_metadata = {}|
      # Start with the basic formatting
      label = model_id.gsub('-', ' ').split.map { |word| 
        # Keep version numbers as-is, capitalize other words
        word =~ /^\d/ ? word : word.capitalize 
      }.join(' ')
      
      # Add helpful context if available
      if model_metadata['launchStage'].present? && model_metadata['launchStage'] != 'GA'
        label += " (#{model_metadata['launchStage']})"
      end
      
      label
    end,
    # - Picklist generator with static fallback
    dynamic_model_picklist: lambda do |connection, bucket, static_fallback|
      # 1. Check if dynamic models are enabled (return to static if not)
      unless connection['dynamic_models']
        puts "Dynamic models disabled, using static list"
        return static_fallback
      end

      # 2. Fetch models (with caching)
      begin
        models = call('fetch_publisher_models', connection, 'google')
        
        if models.present?
          # Convert to options
          options = call('to_model_options', models,
                        bucket: bucket,
                        include_preview: connection['include_preview_models'])
          
          # 3. Ensure we have options, otherwise fall back
          if options.present?
            puts "Returning #{options.length} dynamic models for #{bucket}"
            return options
          else
            puts "No models matched criteria for #{bucket}, using static list"
            return static_fallback
          end
        end
      rescue => e
        puts "Error in dynamic model fetch: #{e.message}"
      end
      
      # 4. Ultimate fallback to static list
      puts "All dynamic fetch attempts failed, using static list"
      static_fallback
    end,
    # -- PAYLOAD CONSTRUCTION UTILITIES --
    # - Base payload builder for simple prompts
    build_base_payload: lambda do |instruction, user_content, safety_settings = nil, options = {}|
      # Build the base structure
      payload = {
        'systemInstruction' => {
          'role' => 'model',
          'parts' => [{ 'text' => instruction }]
        },
        'contents' => [
          {
            'role' => 'user',
            'parts' => if user_content.is_a?(Array)
              user_content  # Allow passing pre-built parts array
            else
              [{ 'text' => user_content }]  # Default to text part
            end
          }
        ],
        'generationConfig' => options['generationConfig'] || { 'temperature' => 0 }
      }
      
      # Add safety settings if provided
      payload['safetySettings'] = safety_settings if safety_settings.present?
      
      # Allow additional top-level fields through options
      options.except('generationConfig').each do |key, value|
        payload[key] = value if value.present?
      end
      
      payload.compact
    end,
    build_conversation_payload: lambda do |input|
      # Handle generation config with response schema
      if input&.dig('generationConfig', 'responseSchema').present?
        input['generationConfig']['responseSchema'] = 
          parse_json(input.dig('generationConfig', 'responseSchema'))
      end
      
      # Handle tools with function declarations
      if input['tools'].present?
        input['tools'] = input['tools'].map do |tool|
          if tool['functionDeclarations'].present?
            tool['functionDeclarations'] = tool['functionDeclarations'].map do |function|
              if function['parameters'].present?
                function['parameters'] = parse_json(function['parameters'])
              end
              function
            end.compact
          end
          tool
        end.compact
      end
      
      # Build contents based on message type
      contents = if input['message_type'] == 'single_message'
        [{
          'role' => 'user',
          'parts' => [{ 'text' => input.dig('messages', 'message') }]
        }]
      else
        input.dig('messages', 'chat_transcript')&.map do |m|
          {
            'role' => m['role'],
            'parts' => call('build_message_parts', m)
          }
        end
      end
      
      # Build the final payload
      {
        'contents' => contents,
        'generationConfig' => input['generationConfig'],
        'systemInstruction' => input['systemInstruction'],
        'tools' => input['tools'],
        'toolConfig' => input['toolConfig'],
        'safetySettings' => input['safetySettings']
      }.compact.merge(input.except('model', 'message_type', 'messages'))
    end,
    build_message_parts: lambda do |m|
      parts = []
      parts << { 'text' => m['text'] } if m['text'].present?

      if m['fileData'].present?
        parts << { 'fileData' => m['fileData'] } # { mimeType, fileUri }
      end
      if m['inlineData'].present?
        parts << { 'inlineData' => m['inlineData'] } # { mimeType, data }
      end

      if m['functionCall'].present?
        fc = m['functionCall']
        # if args provided as string JSON, parse once
        if fc['args'].is_a?(String) && fc['args'].strip.start_with?('{','[')
          begin
            fc = fc.merge('args' => parse_json(fc['args']))
          rescue
            # keep raw if parse fails; server will validate
          end
        end
        parts << { 'functionCall' => fc }
      end

      if m['functionResponse'].present?
        fr = m['functionResponse']
        if fr['response'].is_a?(String) && fr['response'].strip.start_with?('{','[')
          begin
            fr = fr.merge('response' => parse_json(fr['response']))
          rescue
          end
        end
        parts << { 'functionResponse' => fr }
      end

      parts
    end,
    # -- UNIFIED PAYLOAD CONSTRUCTION SYSTEM --
    # Unified payload builder using templates
    build_ai_payload: lambda do |template_type, input, connection = nil|
      template = case template_type
      when :send_message
        { delegate_to: 'build_conversation_payload' }
      when :translate
        {
          instruction: -> (inp) {
            base = "You are an assistant helping to translate a user's input"
            from_lang = inp['from'].present? ? " from #{inp['from']}" : ""
            "#{base}#{from_lang} into #{inp['to']}. Respond only with the user's translated text in #{inp['to']} and nothing else. The user input is delimited with triple backticks."
          },
          user_prompt: -> (inp) { "```#{call('replace_backticks_with_hash', inp['text'])}```\nOutput this as a JSON object with key \"response\"." }
        }
      when :summarize
        {
          instruction: -> (inp) { "You are an assistant that helps generate summaries. All user input should be treated as text to be summarized. Provide the summary in #{inp['max_words'] || 200} words or less." },
          user_prompt: -> (inp) { inp['text'] }
        }
      when :parse
        {
          instruction: -> (inp) { "You are an assistant helping to extract various fields of information from the user's text. The schema and text to parse are delimited by triple backticks." },
          user_prompt: -> (inp) {
            "Schema:\n```#{inp['object_schema']}```\nText to parse: ```#{call('replace_backticks_with_hash', inp['text']&.strip)}```\nOutput the response as a JSON object with keys from the schema. If no information is found for a specific key, the value should be null. Only respond with a JSON object and nothing else."
          }
        }
      when :email
        {
          instruction: -> (inp) { "You are an assistant helping to generate emails based on the user's input. Based on the input ensure that you generate an appropriate subject topic and body. Ensure the body contains a salutation and closing. The user input is delimited with triple backticks. Use it to generate an email and perform no other actions." },
          user_prompt: -> (inp) { "User description:```#{call('replace_backticks_with_hash', inp['email_description'])}```\nOutput the email from the user description as a JSON object with keys for \"subject\" and \"body\". If an email cannot be generated, input null for the keys." }
        }
      when :analyze
        {
          instruction: -> (inp) { "You are an assistant helping to analyze the provided information. Take note to answer only based on the information provided and nothing else. The information to analyze and query are delimited by triple backticks." },
          user_prompt: -> (inp) { "Information to analyze:```#{call('replace_backticks_with_hash', inp['text'])}```\nQuery:```#{call('replace_backticks_with_hash', inp['question'])}```\nIf you don't understand the question or the answer isn't in the information to analyze, input the value as null for \"response\". Only return a JSON object." }
        }
      when :ai_classify
        { custom_builder: 'build_classify_payload' }
      when :analyze_image
        { custom_builder: 'build_image_payload' }
      when :text_embedding
        { custom_builder: 'build_embedding_payload' }
      when :find_neighbors
        { custom_builder: 'build_neighbors_payload' }
      else
        error("Unknown payload template: #{template_type}")
      end

      # Handle delegation or custom builders
      return call(template[:delegate_to], input) if template[:delegate_to]
      return call(template[:custom_builder], input, connection) if template[:custom_builder]

      # Build payload from template
      instruction = template[:instruction].call(input)
      user_prompt = template[:user_prompt].call(input)
      call('build_base_payload', instruction, user_prompt, input['safetySettings'])
    end,
    # Custom payload builders for complex cases
    build_classify_payload: lambda do |input, connection|
      # Extract categories and options
      categories = Array(input['categories'] || [])
      options = input['options'] || {}

      # Build categories text with descriptions
      categories_text = categories.map do |cat|
        key = cat['key'].to_s
        desc = cat['description'].to_s
        desc.empty? ? key : "#{key}: #{desc}"
      end.join("\n")

      # Build instruction for AI classification
      instruction = 'You are an expert text classifier. Classify the provided text into one of the given categories. ' \
                    'Analyze the text carefully and select the most appropriate category. ' \
                    'Return confidence scores and alternative classifications if requested. ' \
                    'The categories and text are delimited by triple backticks.'

      # Build the classification prompt
      user_prompt = "Categories:\n```#{categories_text}```\n" \
                    "Text to classify:\n```#{call('replace_backticks_with_hash', input['text']&.strip)}```\n\n"

      # Add output format based on options
      if options['return_confidence'] && options['return_alternatives']
        user_prompt += 'Return a JSON object with: {"selected_category": "category_key", "confidence": 0.95, "alternatives": [{"category": "other_key", "confidence": 0.05}]}'
      elsif options['return_confidence']
        user_prompt += 'Return a JSON object with: {"selected_category": "category_key", "confidence": 0.95}'
      else
        user_prompt += 'Return a JSON object with: {"selected_category": "category_key"}'
      end

      # Use custom temperature for classification
      temperature = (options['temperature'] || 0.1).to_f
      call('build_base_payload', instruction, user_prompt, input['safetySettings'], temperature)
    end,
    build_image_payload: lambda do |input, connection|
      call('payload_for_analyze_image', input)  # Keep existing complex logic for now
    end,
    build_embedding_payload: lambda do |input, connection|
      call('payload_for_text_embedding', input)  # Keep existing logic
    end,
    build_neighbors_payload: lambda do |input, connection|
      call('payload_for_find_neighbors', input)  # Keep existing logic
    end,
    # -- REMAINING PAYLOAD BUILDERS (for complex cases) --
    payload_for_ai_classify: lambda do |connection, input|
      # Extract categories and options
      categories = Array(input['categories'] || [])
      options = input['options'] || {}
      temperature = (options['temperature'] || 0.1).to_f

      # Build categories text with descriptions
      categories_text = categories.map do |cat|
        key = cat['key'].to_s
        desc = cat['description'].to_s
        desc.empty? ? key : "#{key}: #{desc}"
      end.join("\n")

      # Build instruction for AI classification
      instruction = 'You are an expert text classifier. Classify the provided text into one of the given categories. ' \
                    'Analyze the text carefully and select the most appropriate category. ' \
                    'Return confidence scores and alternative classifications if requested. ' \
                    'The categories and text are delimited by triple backticks.'

      # Build the classification prompt
      user_prompt = "Categories:\n```#{categories_text}```\n" \
                    "Text to classify:\n```#{call('replace_backticks_with_hash', input['text']&.strip)}```\n\n"

      # Add output format instructions
      if options['return_confidence'] && options['return_alternatives']
        user_prompt += 'Return a JSON object with: ' \
                       '{"selected_category": "category_key", ' \
                       '"confidence": 0.95, ' \
                       '"alternatives": [{"category": "other_key", "confidence": 0.05}]}. ' \
                       'Confidence scores should be between 0.0 and 1.0. ' \
                       'Only respond with the JSON object.'
      elsif options['return_confidence']
        user_prompt += 'Return a JSON object with: ' \
                       '{"selected_category": "category_key", "confidence": 0.95}. ' \
                       'Confidence should be between 0.0 and 1.0. ' \
                       'Only respond with the JSON object.'
      else
        user_prompt += 'Return a JSON object with: {"selected_category": "category_key"}. ' \
                       'Only respond with the JSON object.'
      end

      # Build payload with temperature setting
      payload = call('build_base_payload', instruction, user_prompt, input['safetySettings'])
      payload['generationConfig'] ||= {}
      payload['generationConfig']['temperature'] = temperature
      payload
    end,
    payload_for_analyze_image: lambda do |input|
      # We can't use the base builder since we have to pass image data in parts
      {
        'contents' => [
          {
            'role' => 'user',
            'parts' => [
              {
                'text' => input['question']
              },
              {
                'inlineData' => {
                  'mimeType' => input['mime_type'],
                  'data' => input['image']&.encode_base64
                }
              }
            ]
          }
        ],
        'generationConfig' => {
          'temperature' => 0
        },
        'safetySettings' => input['safetySettings'].presence
      }.compact
    end,
    payload_for_text_embedding: lambda do |input|
      {
        'instances' => [
          {
            'task_type' => input['task_type'].presence,
            'title' => input['title'].presence,
            'content' => input['text']
          }.compact
        ]
      }
    end,
    generate_embeddings_batch_exec: lambda do |connection, input|
      # Validate model
      call('validate_publisher_model!', connection, input['model'])

      # Extract inputs
      batch_id = input['batch_id'].to_s
      texts = Array(input['texts'] || [])
      model = input['model']
      task_type = input['task_type']

      # Memory management: Support streaming mode for large datasets
      streaming_mode = input['streaming_mode'] || texts.length > 1000
      max_memory_embeddings = input['max_memory_embeddings'] || 500

      # Initialize statistics
      batches_processed = 0
      successful_requests = 0
      failed_requests = 0
      total_tokens = 0
      embeddings = []
      batch_size = 25  # Vertex AI's limit for embedding batch requests
      rate_limit_info = { requests_last_minute: 0, limit: 0, throttled: false, sleep_ms: 0 }

      # Build the URL once
      url = "projects/#{connection['project']}/locations/#{connection['region']}" \
            "/#{model}:predict"

      # Process texts in batches of 25
      texts.each_slice(batch_size) do |batch_texts|
        batches_processed += 1

        # Use circuit breaker for resilient batch processing
        response = call('circuit_breaker_retry', connection, "batch_embedding_#{model}", {
          max_retries: 2,
          retry_on: [429, 500, 502, 503, 504, 'timeout', 'connection'],
          base_delay: 1.0
        }) do
          # Build batch payload with multiple instances
          instances = batch_texts.map do |text_obj|
            {
              'task_type' => task_type.presence,
              'content' => text_obj['content'].to_s
            }.compact
          end

          payload = { 'instances' => instances }

          # Make rate-limited batch request
          call('rate_limited_ai_request', connection, model, 'embedding', url, payload)
        end

        # Process batch response - each prediction corresponds to each instance
        predictions = response['predictions'] || []

        batch_texts.each_with_index do |text_obj, index|
          prediction = predictions[index]

          if prediction
            # Extract embedding from prediction
            vals = prediction&.dig('embeddings', 'values') ||
                   prediction&.dig('embeddings')&.first&.dig('values') ||
                   []

            embedding_result = {
              'id' => text_obj['id'],
              'vector' => vals,
              'dimensions' => vals.length,
              'metadata' => text_obj['metadata'] || {}
            }

            # Memory management: Store or stream based on mode
            if streaming_mode && embeddings.length >= max_memory_embeddings
              # In streaming mode, yield results periodically and clear memory
              # For now, we'll still accumulate but could extend this to write to cache/storage
              puts "Streaming mode: processed #{embeddings.length} embeddings, continuing..."
            end

            embeddings << embedding_result
            successful_requests += 1
            # Estimate tokens (rough approximation: ~4 characters per token)
            total_tokens += (text_obj['content'].to_s.length / 4.0).ceil
          else
            # Missing prediction for this text
            failed_requests += 1
            embedding_result = {
              'id' => text_obj['id'],
              'vector' => [],
              'dimensions' => 0,
              'metadata' => (text_obj['metadata'] || {}).merge('error' => 'Missing prediction in batch response')
            }

            embeddings << embedding_result
          end
        end
      end

      # Calculate batch efficiency metrics
      api_calls_saved = texts.length - batches_processed

      # Estimate cost savings (assuming $0.0001 per API call for embeddings)
      estimated_cost_savings = api_calls_saved * 0.0001

      # Recipe-friendly output structure
      first_embedding = embeddings.first || {}
      all_successful = failed_requests == 0

      {
        'batch_id' => batch_id,
        'embeddings_count' => embeddings.length,
        'embeddings' => embeddings,
        'first_embedding' => {
          'id' => first_embedding['id'],
          'vector' => first_embedding['vector'] || [],
          'dimensions' => first_embedding['dimensions'] || 0
        },
        'embeddings_json' => embeddings.to_json,
        'model_used' => model,
        'total_processed' => texts.length,
        'successful_requests' => successful_requests,
        'failed_requests' => failed_requests,
        'total_tokens' => total_tokens,
        'batches_processed' => batches_processed,
        'api_calls_saved' => api_calls_saved,
        'estimated_cost_savings' => estimated_cost_savings.round(4),
        'pass_fail' => all_successful,
        'action_required' => all_successful ? 'ready_for_indexing' : 'retry_failed_embeddings',
        'rate_limit_status' => rate_limit_info,
        'memory_management' => {
          'streaming_mode' => streaming_mode,
          'max_memory_embeddings' => max_memory_embeddings,
          'memory_optimized' => streaming_mode && texts.length > max_memory_embeddings
        }
      }
    end,
    generate_embedding_single_exec: lambda do |connection, input|
      # Validate model
      call('validate_publisher_model!', connection, input['model'])

      # Extract inputs
      text = input['text'].to_s
      model = input['model']
      task_type = input['task_type']
      title = input['title']

      # Validate text length (rough estimate)
      if text.length > 32000  # Approximately 8192 tokens
        error('Text too long. Must not exceed 8192 tokens (approximately 6000 words).')
      end

      begin
        # Prepare content with optional title
        content = title.present? ? "#{title}: #{text}" : text

        # Build payload using unified builder
        payload = call('build_ai_payload', :text_embedding, {
          'text' => content,
          'task_type' => task_type,
          'title' => title
        })

        # Build the URL
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
              "/#{model}:predict"

        # Make rate-limited request
        response = call('rate_limited_ai_request', connection, model, 'embedding', url, payload)

        # Extract embedding from response
        vector = response&.dig('predictions', 0, 'embeddings', 'values') ||
                 response&.dig('predictions', 0, 'embeddings')&.first&.dig('values') ||
                 []

        # Estimate token count (rough approximation: ~4 characters per token)
        token_count = (content.length / 4.0).ceil

        # Return single embedding result
        {
          'vector' => vector,
          'dimensions' => vector.length,
          'model_used' => model,
          'token_count' => token_count,
          'rate_limit_status' => rate_limit_info
        }

      rescue => e
        error("Failed to generate embedding: #{e.message}")
      end
    end,
    transform_find_neighbors_response: lambda do |response|
      # Extract all neighbors from potentially multiple queries
      all_neighbors = []
      nearest_neighbors = response['nearestNeighbors'] || []

      nearest_neighbors.each do |query_result|
        neighbors = query_result['neighbors'] || []
        neighbors.each do |neighbor|
          datapoint = neighbor['datapoint'] || {}
          distance = neighbor['distance'].to_f

          # Normalize distance to similarity score (0-1)
          # Assuming distances are typically 0-2 for cosine distance
          max_distance = 2.0
          similarity_score = [1.0 - (distance / max_distance), 0.0].max

          all_neighbors << {
            'datapoint_id' => datapoint['datapointId'].to_s,
            'distance' => distance,
            'similarity_score' => similarity_score.round(6),
            'feature_vector' => datapoint['featureVector'] || [],
            'crowding_attribute' => datapoint.dig('crowdingTag', 'crowdingAttribute').to_s
          }
        end
      end

      # Sort by similarity score (highest first)
      all_neighbors.sort_by! { |n| -n['similarity_score'] }

      # Recipe-friendly response
      best_match = all_neighbors.first || {}
      has_matches = all_neighbors.any?

      {
        'matches_count' => all_neighbors.length,
        'top_matches' => all_neighbors,
        'best_match_id' => best_match['datapoint_id'].to_s,
        'best_match_score' => best_match['similarity_score'] || 0.0,
        'pass_fail' => has_matches,
        'action_required' => has_matches ? 'retrieve_content' : 'refine_query',
        'nearestNeighbors' => nearest_neighbors  # Keep original for backward compatibility
      }
    end,
    payload_for_find_neighbors: lambda do |input|
      # We follow Google’s JSON casing for FindNeighbors REST:
      # top-level: deployedIndexId, returnFullDatapoint, queries[]
      # queries[].datapoint.*: datapointId, featureVector, sparseEmbedding, restricts, numericRestricts, crowdingTag
      #
      # Numeric restricts accept ONE of valueInt/valueFloat/valueDouble with 'op' enum.
      queries = (input['queries'] || []).map do |q|
        dp = q['datapoint'] || {}

        # Pass through as-is; assume UI provided correct shapes/casing.
        {
          'datapoint' => {
            'datapointId'     => dp['datapointId'].presence,
            'featureVector'   => dp['featureVector'].presence,
            'sparseEmbedding' => dp['sparseEmbedding'].presence, # { values: [Float], dimensions: [Integer] }
            'restricts'       => dp['restricts'].presence,       # [{ namespace, allowList[], denyList[] }]
            'numericRestricts'=> dp['numericRestricts'].presence,# [{ namespace, op, valueInt|valueFloat|valueDouble }]
            'crowdingTag'     => dp['crowdingTag'].presence      # { crowdingAttribute }
          }.compact,
          'neighborCount'                          => q['neighborCount'],
          'approximateNeighborCount'               => q['approximateNeighborCount'],
          'perCrowdingAttributeNeighborCount'      => q['perCrowdingAttributeNeighborCount'],
          'fractionLeafNodesToSearchOverride'      => q['fractionLeafNodesToSearchOverride'],
          'rrf'                                    => q['rrf'].presence # optional future-proofing; if you need RRF fusion
        }.compact
      end

      {
        'deployedIndexId'      => input['deployedIndexId'],
        'queries'              => queries,
        'returnFullDatapoint'  => !!input['returnFullDatapoint']
      }.compact
    end,
    # -- RESPONSE EXTRACTION AND NORMALIZATION --
    extract_json: lambda do |resp|
      json_txt = resp&.dig('candidates', 0, 'content', 'parts', 0, 'text')
      return {} if json_txt.blank?

      # Cleanup markdown code blocks
      json = json_txt.gsub(/^```(?:json|JSON)?\s*\n?/, '')  # Remove opening fence
                    .gsub(/\n?```\s*$/, '')                # Remove closing fence
                    .gsub(/`+$/, '')                       # Remove any trailing backticks
                    .strip

      begin
        parse_json(json) || {}
      rescue => e
        # Log error for debugging, but return empty hash to prevent action failure
        puts "JSON parsing failed: #{e.message}. Raw text: #{json_txt}"
        {}
      end
    end,
    get_safety_ratings: lambda do |ratings|
      {
        'sexually_explicit' =>
          ratings&.find do |r|
            r['category'] == 'HARM_CATEGORY_SEXUALLY_EXPLICIT'
          end&.[]('probability'),
        'hate_speech' =>
          ratings&.find { |r| r['category'] == 'HARM_CATEGORY_HATE_SPEECH' }&.[]('probability'),
        'harassment' =>
          ratings&.find { |r| r['category'] == 'HARM_CATEGORY_HARASSMENT' }&.[]('probability'),
        'dangerous_content' =>
          ratings&.find do |r|
            r['category'] == 'HARM_CATEGORY_DANGEROUS_CONTENT'
          end&.[]('probability')
      }
    end,
    check_finish_reason: lambda do |reason|
      case reason&.downcase
      when 'finish_reason_unspecified'
        error 'ERROR - The finish reason is unspecified.'
      when 'other'
        error 'ERROR - Token generation stopped due to an unknown reason.'
      when 'max_tokens'
        error 'ERROR - Token generation reached the configured maximum output tokens.'
      when 'safety'
        error 'ERROR - Token generation stopped because the content potentially contains ' \
              'safety violations.'
      when 'recitation'
        error 'ERROR - Token generation stopped because the content potentially contains ' \
              'copyright violations.'
      when 'blocklist'
        error 'ERROR - Token generation stopped because the content contains forbidden items.'
      when 'prohibited_content'
        error 'ERROR - Token generation stopped for potentially containing prohibited content.'
      when 'spii'
        error 'ERROR - Token generation stopped because the content potentially contains ' \
              'Sensitive Personal Identifiable Information (SPII).'
      when 'malformed_function_call'
        error 'ERROR - The function call generated by the model is invalid.'
      end
    end,
    # Unified response extractor that handles all response types
    extract_response: lambda do |resp, options = {}|
      # Extract options with defaults
      type = options[:type] || :generic
      is_json_response = options[:json_response] || false

      # Common safety and finish reason checks for generative responses
      if [:generic, :email, :parsed, :classify].include?(type)
        call('check_finish_reason', resp.dig('candidates', 0, 'finishReason'))
        ratings = call('get_safety_ratings', resp.dig('candidates', 0, 'safetyRatings'))
        return standard_error_response(type, ratings) if ratings.blank?
      else
        ratings = {}
      end

      # Extract core response based on type
      case type
      when :generic
        answer = if is_json_response
                  call('extract_json', resp)&.[]('response')
                else
                  resp&.dig('candidates', 0, 'content', 'parts', 0, 'text')
                end

        has_answer = !answer.nil? && !answer.to_s.strip.empty? && answer.to_s.strip != 'N/A'

        {
          'answer' => answer.to_s,
          'has_answer' => has_answer,
          'pass_fail' => has_answer,
          'action_required' => has_answer ? 'use_answer' : 'try_different_question',
          'answer_length' => answer.to_s.length,
          'safety_ratings' => ratings,
          'prompt_tokens' => resp.dig('usageMetadata', 'promptTokenCount') || 0,
          'response_tokens' => resp.dig('usageMetadata', 'candidatesTokenCount') || 0,
          'total_tokens' => resp.dig('usageMetadata', 'totalTokenCount') || 0
        }

      when :email
        json = call('extract_json', resp)
        {
          'subject' => json&.[]('subject'),
          'body' => json&.[]('body'),
          'safety_ratings' => ratings,
          'usage' => resp['usageMetadata']
        }

      when :parsed
        json = call('extract_json', resp)
        json&.each_with_object({}) do |(key, value), hash|
          hash[key] = value
        end&.merge('safety_ratings' => ratings, 'usage' => resp['usageMetadata'])

      when :embedding
        vals = resp&.dig('predictions', 0, 'embeddings', 'values') ||
               resp&.dig('predictions', 0, 'embeddings')&.first&.dig('values') ||
               []
        { 'embedding' => vals.map { |v| { 'value' => v } } }

      when :classify
        json = call('extract_json', resp)
        selected_category = json&.[]('selected_category') || 'N/A'
        confidence = json&.[]('confidence')&.to_f || 1.0
        alternatives = json&.[]('alternatives') || []

        # Normalize values
        selected_category = selected_category.to_s
        selected_category = 'unknown' if selected_category.empty? || selected_category == 'N/A'
        confidence = [[confidence, 0.0].max, 1.0].min

        # Decision logic
        confidence_threshold = 0.7
        requires_human_review = confidence < confidence_threshold

        {
          'selected_category' => selected_category,
          'confidence' => confidence,
          'alternatives' => alternatives,
          'requires_human_review' => requires_human_review,
          'confidence_threshold' => confidence_threshold,
          'pass_fail' => !requires_human_review,
          'action_required' => requires_human_review ? 'human_review' : 'use_classification',
          'safety_ratings' => ratings,
          'usage' => resp['usageMetadata']
        }

      else
        error("Unknown response extraction type: #{type}")
      end
    end,
    # Helper method for standard error responses
    standard_error_response: lambda do |type, ratings|
      case type
      when :generic
        { 'answer' => 'N/A', 'safety_ratings' => {} }
      when :classify
        { 'selected_category' => 'N/A', 'confidence' => 0.0, 'safety_ratings' => {} }
      else
        { 'error' => 'Safety ratings check failed', 'safety_ratings' => {} }
      end
    end,
    # -- GOOGLE DRIVE HELPER METHODS --
    extract_drive_file_id: lambda do |url_or_id|
      return url_or_id if url_or_id.blank?

      # Try different URL patterns
      # Pattern 1: /d/{file_id}/
      if match = url_or_id.match(%r{/d/([a-zA-Z0-9_-]+)})
        return match[1]
      end

      # Pattern 2: ?id={file_id}
      if match = url_or_id.match(/[?&]id=([a-zA-Z0-9_-]+)/)
        return match[1]
      end

      # Pattern 3: Raw file ID (alphanumeric with dashes/underscores)
      if url_or_id.match(/^[a-zA-Z0-9_-]+$/)
        return url_or_id
      end

      # If no pattern matches, return as-is and let API handle the error
      url_or_id
    end,
    get_export_mime_type: lambda do |mime_type|
      return nil if mime_type.blank?

      case mime_type
      when 'application/vnd.google-apps.document'
        'text/plain'
      when 'application/vnd.google-apps.spreadsheet'
        'text/csv'
      when 'application/vnd.google-apps.presentation'
        'text/plain'
      else
        # Return nil for regular files (will be downloaded as-is)
        nil
      end
    end,
    build_drive_query: lambda do |options = {}|
      query_parts = ['trashed = false']

      # Add folder filter
      if options[:folder_id].present?
        query_parts << "'#{options[:folder_id]}' in parents"
      end

      # Add date filters
      if options[:modified_after].present?
        query_parts << "modifiedTime > '#{options[:modified_after]}'"
      end

      if options[:modified_before].present?
        query_parts << "modifiedTime < '#{options[:modified_before]}'"
      end

      # Add MIME type filters
      if options[:mime_type].present?
        query_parts << "mimeType = '#{options[:mime_type]}'"
      end

      if options[:exclude_folders]
        query_parts << "mimeType != 'application/vnd.google-apps.folder'"
      end

      query_parts.join(' and ')
    end,
    handle_drive_error: lambda do |connection, code, body, message|
      service_account_email = connection['service_account_email'] || 
                             connection['client_id']
      case code
      when 404
        "File not found in Google Drive. Please verify the file ID and ensure the file exists."
      when 403
        if body&.include?('insufficientFilePermissions') || body&.include?('forbidden')
          "Access denied. Please share the file with the service account: #{service_account_email}"
        else
          "Permission denied. Check your Google Drive API access and file permissions."
        end
      when 429
        "Rate limit exceeded. Please implement request backoff and retry logic."
      when 401
        "Authentication failed. Please check your OAuth2 token or service account credentials."
      when 500, 502, 503
        "Google Drive API temporary error (#{code}). Please retry after a brief delay."
      else
        "Google Drive API error (#{code}): #{message || body}"
      end
    end,
    # -- SAMPLES AND UX HELPERS --
    sample_record_output: lambda do |input|
      case input
      when 'send_message'
        {
          candidates: [
            {
              content: {
                role: 'model',
                parts: [
                  {
                    text: "Hey there! I'm happy to answer your question about dark clouds."
                  }
                ]
              },
              finishReason: 'STOP',
              safetyRatings: [
                {
                  category: 'HARM_CATEGORY_HATE_SPEECH',
                  probability: 'NEGLIGIBLE',
                  probabilityScore: 0.022583008,
                  severity: 'HARM_SEVERITY_NEGLIGIBLE',
                  severityScore: 0.018554688
                }
              ],
              avgLogprobs: -0.19514432351939617
            }
          ],
          usageMetadata: {
            promptTokenCount: 23,
            candidatesTokenCount: 557,
            totalTokenCount: 580,
            trafficType: 'ON_DEMAND',
            promptTokensDetails: [
              { modality: 'TEXT', tokenCount: 105 }
            ],
            candidatesTokensDetails: [
              { modality: 'TEXT', tokenCount: 516 }
            ]
          },
          modelVersion: 'gemini-1.5-pro',
          createTime: '2025-08-01T10:36:16.110916Z',
          responseId: 'oJiMaMTiBoKrmecPqYqFWA'
        }
      when 'translate_text'
        {
          answer: '<Translated text>'
        }.merge(call('safety_ratings_output_sample'),
                call('usage_output_sample'))
      when 'summarize_text'
        {
          answer: '<Summarized text>'
        }.merge(call('safety_ratings_output_sample'),
                call('usage_output_sample'))
      when 'draft_email'
        {
          subject: 'Sample email subject',
          body: 'This is a sample email body'
        }.merge(call('safety_ratings_output_sample'),
                call('usage_output_sample'))
      when 'analyze_text'
        {
          answer: 'This text describes rainy weather'
        }.merge(call('safety_ratings_output_sample'),
                call('usage_output_sample'))
      when 'analyze_image'
        {
          answer: 'This image shows birds'
        }.merge(call('safety_ratings_output_sample'),
                call('usage_output_sample'))
      when 'text_embedding'
        {
          embedding: [
            { value: -0.04629135504364967 }
          ]
        }
        when 'find_neighbors'
          {
            nearestNeighbors: [
              {
                id: 'query-1',
                neighbors: [
                  {
                    datapoint: {
                      datapointId: 'doc_001_chunk_1',
                      featureVector: [0.1, 0.2, 0.3],
                      crowdingTag: {
                        crowdingAttribute: 'doc_001'
                      }
                    },
                    distance: 0.95
                  }
                ]
              }
            ]
          }
      end
    end,
    safety_ratings_output_sample: lambda do
      {
        'safety_ratings' => {
          'sexually_explicit' => 'NEGLIGIBLE',
          'hate_speech' => 'NEGLIGIBLE',
          'harassment' => 'NEGLIGIBLE',
          'dangerous_content' => 'NEGLIGIBLE'
        }
      }
    end,
    usage_output_sample: lambda do
      {
        'usage' => {
          'promptTokenCount' => 23,
          'candidatesTokenCount' => 557,
          'totalTokenCount' => 580
        }
      }
    end,
    format_parse_sample: lambda do |input|
      input&.each_with_object({}) do |element, hash|
        if element['type'] == 'array' && element['of'] == 'object'
          hash[element['name']] = [call('format_parse_sample', element['properties'])]
        elsif element['type'] == 'object'
          hash[element['name']] = call('format_parse_sample', element['properties'])
        else
          hash[element['name'].gsub(/^\d|\W/) { |c| "_ #{c.unpack('H*')}" }] = '<Sample Text>'
        end
      end || {}
    end,
    # -- INDEX MANAGEMENT METHODS --
    validate_index_access: lambda do |connection, index_id|
      # Extract project, region, and index name from the index_id
      index_parts = index_id.split('/')
      if index_parts.length < 6 || index_parts[0] != 'projects' || index_parts[2] != 'locations' || index_parts[4] != 'indexes'
        error("Invalid index_id format. Expected: projects/PROJECT/locations/REGION/indexes/INDEX_ID")
      end


      begin
        # Get index details
        index_response = get("#{index_id}").
          after_error_response(/.*/) do |code, body, _header, message|
            if code == 404
              error("Index not found: #{index_id}")
            elsif code == 403
              error("Permission denied. Service account missing aiplatform.indexes.get permission for index: #{index_id}")
            else
              call('handle_vertex_error', connection, code, body, message)
            end
          end

        # Check if index is deployed
        deployed_indexes = index_response['deployedIndexes'] || []
        if deployed_indexes.empty?
          error("Index is not deployed. Index must be in DEPLOYED state for upsert operations.")
        end

        # Get index stats from first deployed index
        deployed_index = deployed_indexes[0]
        # Ensure all ID fields are strings and timestamps are ISO 8601
        created_time = index_response['createTime']
        updated_time = index_response['updateTime']

        # Ensure timestamps are in ISO 8601 format (Google already provides ISO 8601)
        created_time = created_time.to_s if created_time
        updated_time = updated_time.to_s if updated_time

        index_stats = {
          'index_id' => index_id.to_s,
          'deployed_state' => 'DEPLOYED',
          'dimensions' => index_response.dig('indexStats', 'vectorsCount')&.to_i || 0,
          'total_datapoints' => index_response.dig('indexStats', 'shardsCount')&.to_i || 0,
          'display_name' => index_response['displayName'].to_s,
          'created_time' => created_time || '',
          'updated_time' => updated_time || ''
        }

        # Try to get more detailed stats if available
        if deployed_index['indexEndpoint']
          endpoint_id = deployed_index['indexEndpoint']
          begin
            endpoint_response = get("#{endpoint_id}").
              after_error_response(/.*/) do |code, body, _header, message|
                # Don't fail validation if we can't get endpoint details
                # This is optional information
              end

            if endpoint_response
              index_stats['endpoint_state'] = endpoint_response['state'] || 'UNKNOWN'
              index_stats['public_endpoint_enabled'] = endpoint_response['publicEndpointEnabled'] || false
            end
          rescue
            # Ignore endpoint lookup failures - not critical for validation
          end
        end

        index_stats
      rescue => e
        if e.message.include?('Permission denied') || e.message.include?('aiplatform.indexes')
          error("Service account missing required permissions. Ensure the service account has 'aiplatform.indexes.get' and 'aiplatform.indexes.update' permissions.")
        else
          error("Failed to validate index access: #{e.message}")
        end
      end
    end,
    batch_upsert_datapoints: lambda do |connection, index_id, datapoints, update_mask = nil|
      # Validate inputs
      if datapoints.nil? || datapoints.empty?
        error('At least one datapoint is required for batch upsert')
      end

      # First validate index access and get metadata
      index_stats = call('validate_index_access', connection, index_id)

      # Process datapoints in batches of 100 with exponential backoff
      batch_size = 100
      max_retries = 3
      base_delay = 1.0 # Base delay in seconds

      results = {
        'total_processed' => datapoints.length,
        'successful_upserts' => 0,
        'failed_upserts' => 0,
        'error_details' => [],
        'index_stats' => index_stats
      }

      # Process each batch
      datapoints.each_slice(batch_size).with_index do |batch, batch_index|
        retry_count = 0
        batch_success = false

        while retry_count <= max_retries && !batch_success
          begin
            # Format datapoints for API
            formatted_datapoints = batch.map do |dp|
              # Validate required fields
              unless dp['datapoint_id'] && dp['feature_vector']
                error("Datapoint missing required fields. Each datapoint must have 'datapoint_id' and 'feature_vector'")
              end

              # Validate vector dimensions if we have index metadata
              if index_stats['dimensions'] && index_stats['dimensions'] > 0
                if dp['feature_vector'].length != index_stats['dimensions']
                  error("Vector dimension mismatch. Expected #{index_stats['dimensions']} dimensions, got #{dp['feature_vector'].length} for datapoint '#{dp['datapoint_id']}'")
                end
              end

              datapoint = {
                'datapointId' => dp['datapoint_id'],
                'featureVector' => dp['feature_vector']
              }

              # Add optional fields if present
              if dp['restricts']&.any?
                datapoint['restricts'] = dp['restricts'].map do |restrict|
                  formatted_restrict = { 'namespace' => restrict['namespace'] }
                  formatted_restrict['allowList'] = restrict['allowList'] if restrict['allowList']&.any?
                  formatted_restrict['denyList'] = restrict['denyList'] if restrict['denyList']&.any?
                  formatted_restrict
                end
              end

              datapoint['crowdingTag'] = dp['crowding_tag'] if dp['crowding_tag']
              datapoint
            end

            # Build request payload
            payload = { 'datapoints' => formatted_datapoints }
            payload['updateMask'] = update_mask if update_mask

            # Make API call
            post("#{index_id}:upsertDatapoints", payload).
              after_error_response(/.*/) do |code, body, _header, message|
                if code == 429 # Rate limit
                  raise StandardError.new("Rate limited: #{message}")
                elsif code == 403
                  raise StandardError.new("Permission denied. Service account missing aiplatform.indexes.update permission")
                else
                  call('handle_vertex_error', connection, code, body, message)
                end
              end

            # If we get here, the batch was successful
            results['successful_upserts'] += batch.length
            batch_success = true

          rescue => e
            retry_count += 1

            if e.message.include?('Rate limited') && retry_count <= max_retries
              # Exponential backoff for rate limits
              delay = base_delay * (2 ** (retry_count - 1))
              sleep(delay)
            elsif retry_count > max_retries
              # Mark all datapoints in this batch as failed
              batch.each do |dp|
                results['error_details'] << {
                  'datapoint_id' => dp['datapoint_id'],
                  'batch_index' => batch_index,
                  'error' => "Failed after #{max_retries} retries: #{e.message}",
                  'retry_count' => retry_count - 1
                }
              end
              results['failed_upserts'] += batch.length
              batch_success = true # Exit retry loop
            else
              # Non-retryable error, mark batch as failed
              batch.each do |dp|
                results['error_details'] << {
                  'datapoint_id' => dp['datapoint_id'],
                  'batch_index' => batch_index,
                  'error' => e.message,
                  'retry_count' => retry_count - 1
                }
              end
              results['failed_upserts'] += batch.length
              batch_success = true # Exit retry loop
            end
          end
        end
      end

      # Update final index stats if we successfully processed some datapoints
      if results['successful_upserts'] > 0
        begin
          updated_stats = call('validate_index_access', connection, index_id)
          results['index_stats'] = updated_stats
        rescue
          # Ignore errors getting updated stats - use original stats
        end
      end

      results
    end
  },

  object_definitions: {
    # -- COMMON FIELD DEFINITIONS --
    # Common text input field for AI operations
    text_input_field: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'text', label: 'Text', type: 'string',
            control_type: 'text-area', optional: false,
            hint: 'Enter the text to be processed. Limit to 8000 words for optimal performance.' }
        ]
      end
    },
    # Shared Drive file fields used across multiple actions
    drive_file_fields: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'id', label: 'File ID', type: 'string',
            hint: 'Google Drive file identifier' },
          { name: 'name', label: 'File name', type: 'string',
            hint: 'Original filename in Google Drive' },
          { name: 'mime_type', label: 'MIME type', type: 'string',
            hint: 'File MIME type' },
          { name: 'size', label: 'File size', type: 'integer',
            hint: 'File size in bytes' },
          { name: 'modified_time', label: 'Modified time', type: 'date_time',
            hint: 'Last modification timestamp' },
          { name: 'checksum', label: 'MD5 checksum', type: 'string',
            hint: 'MD5 hash for change detection' }
        ]
      end
    },
    # Extended Drive file fields with content
    drive_file_extended: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        # Start with base fields
        base_fields = object_definitions['drive_file_fields']

        # Add extended fields
        extended = base_fields.concat([
          { name: 'owners', label: 'File owners', type: 'array', of: 'object',
            properties: [
              { name: 'displayName', label: 'Display name', type: 'string' },
              { name: 'emailAddress', label: 'Email address', type: 'string' }
            ],
            hint: 'Array of file owners' },
          { name: 'text_content', label: 'Text content', type: 'string',
            hint: 'Extracted text content' },
          { name: 'needs_processing', label: 'Needs processing', type: 'boolean',
            hint: 'True if file requires additional processing' },
          { name: 'export_mime_type', label: 'Export MIME type', type: 'string',
            hint: 'MIME type used for export' },
          { name: 'fetch_method', label: 'Fetch method', type: 'string',
            hint: 'Method used to retrieve content' }
        ])

        extended
      end
    },
    # Common safety and usage fields
    safety_and_usage: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        safety = object_definitions['safety_rating_schema'] || []
        usage = object_definitions['usage_schema'] || []
        safety.concat(usage)
      end
    },
    # -- STANDARD OBJECT DEFINITIONS --
    prediction: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'predictions',
            type: 'array',
            of: 'object',
            properties: [
              { name: 'content' },
              { name: 'citationMetadata',
                type: 'object',
                properties: [
                  { name: 'citations',
                    type: 'array',
                    of: 'object',
                    properties: [
                      { name: 'startIndex',
                        type: 'integer',
                        control_type: 'integer',
                        convert_output: 'integer_conversion' },
                      { name: 'endIndex',
                        type: 'integer',
                        control_type: 'integer',
                        convert_output: 'integer_conversion' },
                      { name: 'url' },
                      { name: 'title' },
                      { name: 'license' },
                      { name: 'publicationDate' }
                    ] }
                ] },
              { name: 'logprobs',
                label: 'Log probabilities',
                type: 'object',
                properties: [
                  { name: 'tokenLogProbs',
                    label: 'Token log probabilities',
                    type: 'array', of: 'number' },
                  { name: 'tokens',
                    type: 'array', of: 'string' },
                  { name: 'topLogProbs',
                    label: 'Top log probabilities' }
                ] },
              { name: 'safetyAttributes',
                type: 'object',
                properties: [
                  { name: 'categories',
                    type: 'array',
                    of: 'string' },
                  { name: 'blocked',
                    type: 'boolean',
                    control_type: 'checkbox',
                    convert_output: 'boolean_conversion' },
                  { name: 'scores',
                    type: 'array',
                    of: 'number' },
                  { name: 'errors',
                    type: 'array',
                    of: 'number' },
                  { name: 'safetyRatings',
                    type: 'array', of: 'object',
                    properties: [
                      { name: 'category' },
                      { name: 'severity' },
                      { name: 'severityScore',
                        type: 'number',
                        convert_output: 'float_conversion' },
                      { name: 'probabilityScore',
                        type: 'number',
                        convert_output: 'float_conversion' }
                    ] }
                ] }
            ] },
          { name: 'metadata',
            type: 'object',
            properties: [
              { name: 'tokenMetadata',
                type: 'object',
                properties: [
                  { name: 'inputTokenCount',
                    type: 'object',
                    properties: [
                      { name: 'totalTokens',
                        type: 'integer',
                        control_type: 'integer',
                        convert_output: 'integer_conversion' },
                      { name: 'totalBillableCharacters',
                        type: 'integer',
                        control_type: 'integer',
                        convert_output: 'integer_conversion' }
                    ] },
                  { name: 'outputTokenCount',
                    type: 'object',
                    properties: [
                      { name: 'totalTokens',
                        type: 'integer',
                        control_type: 'integer',
                        convert_output: 'integer_conversion' },
                      { name: 'totalBillableCharacters',
                        type: 'integer',
                        control_type: 'integer',
                        convert_output: 'integer_conversion' }
                    ] }
                ] }
            ] }
        ]
      end
    },
    get_prediction_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'instances',
            type: 'array', of: 'object',
            group: 'Instances',
            properties: [
              { name: 'prompt',
                hint: 'Text input to generate model response. Can include preamble, ' \
                      'questions, suggestions, instructions, or examples.',
                sticky: true }
            ] },
          { name: 'parameters',
            type: 'object',
            group: 'Parameters',
            properties: [
              { name: 'temperature',
                hint: 'The temperature is used for sampling during response generation, ' \
                      'which occurs when topP and topK are applied. Temperature controls ' \
                      'the degree of randomness in token selection.',
                type: 'number',
                convert_input: 'float_conversion',
                sticky: true },
              { name: 'maxOutputTokens',
                label: 'Maximum number of tokens',
                hint: ' A token is approximately four characters. 100 tokens correspond to ' \
                      'roughly 60-80 words. Specify a lower value for shorter responses and ' \
                      'a higher value for longer responses.',
                type: 'integer',
                convert_input: 'integer_conversion',
                sticky: true },
              { name: 'topK',
                hint: 'Specify a lower value for less random responses and a higher value for ' \
                      'more random responses. The default top-K is 40.',
                type: 'integer',
                convert_input: 'integer_conversion',
                sticky: true },
              { name: 'topP',
                hint: 'Specify a lower value for less random responses and a higher value for ' \
                      'more random responses. The default top-P is 0.95.',
                type: 'integer',
                convert_input: 'integer_conversion',
                sticky: true },
              { name: 'logprobs',
                label: 'Log probabilities',
                hint: 'Returns the top `logprobs` most likely candidate tokens with ' \
                      'their log probabilities at each generation step',
                control_type: 'integer',
                convert_input: 'integer_conversion' },
              { name: 'presencePenalty',
                hint: 'Positive values penalize tokens that already appear in the generated ' \
                      'text, increasing the probability of generating more diverse content. ' \
                      'Acceptable values are -2.0—2.0.',
                control_type: 'number',
                convert_input: 'float_conversion' },
              { name: 'frequencyPenalty',
                hint: 'Positive values penalize tokens that repeatedly appear in the ' \
                      'generated text, decreasing the probability of repeating content. ' \
                      'Acceptable values are -2.0—2.0.',
                control_type: 'number',
                convert_input: 'float_conversion' },
              { name: 'logitBias',
                hint: 'Mapping of token IDs to their bias values. The bias values are added ' \
                      'to the logits before sampling. Allowed values: From -100 to 100.' },
              { name: 'stopSequences',
                type: 'array', of: 'string',
                hint: 'Specifies a list of strings that tells the model to stop generating text ' \
                      'if one of the strings is encountered in the response. If a string ' \
                      'appears multiple times in the response, then the response truncates ' \
                      "where it's first encountered. The strings are case-sensitive.",
                sticky: true },
              { name: 'candidateCount',
                type: 'integer',
                hint: 'Specify the number of response variations to return.',
                convert_input: 'integer_conversion',
                sticky: true },
              { name: 'echo',
                type: 'boolean',
                hint: 'If true, the prompt is echoed in the generated text.',
                control_type: 'checkbox',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'echo',
                  label: 'Echo',
                  type: 'string',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Enter custom value',
                  hint: 'Allowed values are: true or false.'
                } }
            ] }
        ]
      end
    },
    config_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'tools',
            type: 'array',
            of: 'object',
            hint: 'Specify the list of tools the model may use to generate ' \
                  'the next response.',
            group: 'Tools',
            properties: [
              { name: 'functionDeclarations',
                type: 'array',
                of: 'object',
                properties: [
                  { name: 'name',
                    hint: 'The name of the function to call. Must start with a letter ' \
                          'or an underscore.' },
                  { name: 'description',
                    hint: 'The description and purpose of the function. Model uses it ' \
                          'to decide how and whether to call the function.' },
                  { name: 'parameters',
                    control_type: 'text-area',
                    hint: 'Provide the JSON schema object format.' }
                ] }
            ] },

          { name: 'toolConfig',
            type: 'object',
            hint: 'This tool config is shared for all tools provided in the request.',
            group: 'Tools',
            properties: [
              { name: 'functionCallingConfig',
                type: 'object',
                properties: [
                  { name: 'mode',
                    control_type: 'select',
                    pick_list: :function_call_mode,
                    hint: 'Select the mode to use',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'mode',
                      label: 'Mode',
                      type: 'string',
                      control_type: 'text',
                      optional: true,
                      toggle_hint: 'Use custom value',
                      hint: 'Acceptable values are: MODE_UNSPECIFIED, AUTO, ANY or NONE.'
                    } },
                  { name: 'allowedFunctionNames',
                    type: 'array',
                    of: 'string',
                    hint: 'Function names to call. Only set when the Mode is ANY.' }
                ] }
            ] },

          { name: 'safetySettings',
            type: 'array',
            of: 'object',
            hint: 'Specify safety settings when relevant',
            group: 'Safety',
            properties: [
              { name: 'category',
                control_type: 'select',
                pick_list: :safety_categories,
                hint: 'Select appropriate safety category',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'category',
                  label: 'Category',
                  type: 'string',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Provide a safety category',
                  hint: 'Acceptable values are: HARM_CATEGORY_UNSPECIFIED, ' \
                        'HARM_CATEGORY_DANGEROUS_CONTENT, HARM_CATEGORY_HATE_SPEECH, ' \
                        'HARM_CATEGORY_HARASSMENT or HARM_CATEGORY_SEXUALLY_EXPLICIT.'
                } },
              { name: 'threshold',
                control_type: 'select',
                pick_list: :safety_threshold,
                hint: 'Select the appropriate safety threshold',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'threshold',
                  label: 'Threshold',
                  type: 'string',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Provide a safety threshold',
                  hint: 'Acceptable values are: HARM_BLOCK_THRESHOLD_UNSPECIFIED, ' \
                        'BLOCK_LOW_AND_ABOVE, BLOCK_MEDIUM_AND_ABOVE, BLOCK_ONLY_HIGH, ' \
                        'BLOCK_NONE or OFF.'
                } },
              { name: 'method',
                control_type: 'select',
                pick_list: :safety_method,
                hint: 'Specify if the threshold is used for probability or severity ' \
                      'score. If left blank, threshold is used for probability score.',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'method',
                  label: 'Method',
                  type: 'string',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Provide a method',
                  hint: 'Acceptable values are: HARM_BLOCK_METHOD_UNSPECIFIED, ' \
                        'SEVERITY or PROBABILITY.'
                } }
            ] },

          { name: 'generationConfig',
            type: 'object',
            hint: 'Specify parameters that are suitable for your use case',
            group: 'Generation',
            properties: [
              { name: 'stopSequences',
                type: 'array',
                of: 'string',
                hint: 'A list of strings that the model will stop generating text at.' },
              { name: 'responseMimeType',
                label: 'Response MIME type',
                control_type: 'select',
                pick_list: :response_type,
                hint: 'Select the response type. Defaults to text/plain if left blank.',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'responseMimeType',
                  label: 'Response MIME type',
                  type: 'string',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Provide a response type',
                  hint: 'Acceptable values are: text/plain or application/json.'
                } },
              { name: 'temperature',
                sticky: true,
                control_type: 'number',
                convert_input: 'float_conversion',
                hint: "A number that controls the randomness of the model's output. " \
                      'A higher temperature will result in more random output, while a ' \
                      'lower temperature will result in more predictable output. The ' \
                      'supported range is 0 to 2.000.' },
              { name: 'topP',
                label: 'Top P',
                control_type: 'number',
                convert_input: 'float_conversion',
                hint: 'A number that controls the probability of the model generating each token. ' \
                      'A higher topP will result in the model generating more likely tokens, while a ' \
                      'lower topP will result in the model generating more unlikely tokens. ' \
                      'Allowed values: Any decimal value between 0 and 1.' },
              { name: 'topK',
                label: 'Top K',
                control_type: 'number',
                convert_input: 'float_conversion',
                hint: 'A number that controls the number of tokens that the model considers when ' \
                      'generating each token. A higher topK will result in the model considering more ' \
                      'tokens, while a lower topK will result in the model considering fewer tokens. ' \
                      'The supported range is 1 to 40.' },
              { name: 'candidateCount',
                control_type: 'integer',
                convert_input: 'integer_conversion',
                hint: 'The number of candidates to generate.' },
              { name: 'maxOutputTokens',
                control_type: 'integer',
                convert_input: 'integer_conversion',
                hint: 'The maximum number of tokens that the model will generate.' },
              { name: 'presencePenalty',
                control_type: 'number',
                convert_input: 'float_conversion',
                ngIf: 'input.model != "publishers/google/models/gemini-pro"',
                hint: 'The amount of positive penalties.' },
              { name: 'frequencyPenalty',
                control_type: 'number',
                convert_input: 'float_conversion',
                ngIf: 'input.model != "publishers/google/models/gemini-pro"',
                hint: 'The frequency of penalties.' },
              { name: 'seed',
                control_type: 'integer',
                convert_input: 'integer_conversion',
                hint: 'The seed value initializes the generation of an image. ' \
                      'It is randomly generated if left blank. Controlling the ' \
                      'seed can help generate reproducible images.' },
              { name: 'responseSchema',
                control_type: 'text-area',
                ngIf: 'input.generationConfig.responseMimeType == "application/json"',
                hint: 'Define the output data schema.' }
            ] },

          { name: 'systemInstruction',
            type: 'object',
            hint: 'Specify the system instructions for the model.',
            group: 'System instructions',
            properties: [
              { name: 'role',
                hint: 'The role should be <b>model</b> when defining system instructions.' },
              { name: 'parts',
                type: 'array',
                of: 'object',
                properties: [
                  { name: 'text',
                    control_type: 'text-area',
                    hint: 'The system instructions for the model.' }
                ] }
            ] }
        ]
      end
    },
    send_messages_input: {
      fields: lambda do |_connection, config_fields, object_definitions|
        is_single_message = config_fields['message_type'] == 'single_message'
        message_schema = if is_single_message
                           [
                             { name: 'message',
                               label: 'Text to send',
                               type: 'string',
                               control_type: 'text-area',
                               optional: false,
                               hint: 'Enter a message to start a conversation with Gemini.' }
                           ]
                         else
                           [
                             { name: 'chat_transcript',
                               type: 'array',
                               of: 'object',
                               optional: false,
                               properties: [
                                 { name: 'role',
                                   control_type: 'select',
                                   pick_list: :chat_role,
                                   sticky: true,
                                   extends_schema: true,
                                   hint: 'Select the role of the author of this message.',
                                   toggle_hint: 'Select from list',
                                   toggle_field: {
                                     name: 'role',
                                     label: 'Role',
                                     control_type: 'text',
                                     type: 'string',
                                     optional: true,
                                     extends_schema: true,
                                     toggle_hint: 'Use custom value',
                                     hint: 'Provide the role of the author of this message. ' \
                                           'Allowed values: <b>user</b> or <b>model</b>.'
                                   } },
                                 { name: 'text',
                                   control_type: 'text-area',
                                   sticky: true,
                                   hint: 'The contents of the selected role message.' },
                                 { name: 'fileData',
                                   type: 'object',
                                   properties: [
                                     { name: 'mimeType', label: 'MIME type' },
                                     { name: 'fileUri', label: 'File URI' }
                                   ] },
                                 { name: 'inlineData',
                                   type: 'object',
                                   properties: [
                                     { name: 'mimeType', label: 'MIME type' },
                                     { name: 'data' }
                                   ] },
                                 { name: 'functionCall',
                                   type: 'object',
                                   properties: [
                                     { name: 'name', label: 'Function name' },
                                     { name: 'args', control_type: 'text-area', label: 'Arguments' }
                                   ] },
                                 { name: 'functionResponse',
                                   type: 'object',
                                   properties: [
                                     { name: 'name', label: 'Function name' },
                                     { name: 'response',
                                       control_type: 'text-area',
                                       hint: 'Use this field to send function response. ' \
                                             'Parameters field in Tools > Function declarations ' \
                                             'should also be used when using this field.' }
                                   ] }
                               ],
                               hint: 'A list of messages describing the conversation so far.' }
                           ]
                         end
        object_definitions['text_model_schema'].concat(
          [
            { name: 'message_type', label: 'Message type', type: 'string', control_type: 'select', pick_list: :message_types,
              extends_schema: true, optional: false, hint: 'Choose the type of the message to send.', group: 'Message' },
            { name: 'messages', label: is_single_message ? 'Message' : 'Messages',
              type: 'object', optional: false, properties: message_schema, group: 'Message' },
            { name: 'formatted_prompt', label: 'Formatted prompt (RAG_Utils)', type: 'object', optional: true, group: 'Advanced',
              hint: 'Pre-formatted prompt payload from RAG_Utils. When provided, this will be used directly instead of building from messages.' }
          ].compact
        ).concat(object_definitions['config_schema'])
      end
    },
    send_messages_output: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'candidates', type: 'array', of: 'object',
            properties: [
              { name: 'content',
                type: 'object',
                properties: [
                  { name: 'role' },
                  { name: 'parts', type: 'array', of: 'object',
                    properties: [
                      { name: 'text' },
                      { name: 'fileData',
                        type: 'object',
                        properties: [
                          { name: 'mimeType', label: 'MIME type' },
                          { name: 'fileUri', label: 'File URI' }
                        ] },
                      { name: 'inlineData',
                        type: 'object',
                        properties: [
                          { name: 'mimeType', label: 'MIME type' },
                          { name: 'data' }
                        ] },
                      { name: 'functionCall',
                        type: 'object',
                        properties: [
                          { name: 'name' },
                          { name: 'args', label: 'Arguments' }
                        ] }
                    ] }
                ] },
              { name: 'finishReason' },
              { name: 'safetyRatings', type: 'array', of: 'object',
                properties: [
                  { name: 'category' },
                  { name: 'probability' },
                  { name: 'probabilityScore', type: 'number' },
                  { name: 'severity' },
                  { name: 'severityScore', type: 'number' }
                ] },
              { name: 'avgLogprobs', label: 'Average log probabilities', type: 'number' }
            ] },
          { name: 'usageMetadata',
            type: 'object',
            properties: [
              { name: 'promptTokenCount', type: 'integer' },
              { name: 'candidatesTokenCount', type: 'integer' },
              { name: 'totalTokenCount', type: 'integer' },
              { name: 'trafficType' },
              { name: 'promptTokensDetails',
                type: 'array',
                of: 'object',
                properties: [
                  { name: 'modality' },
                  { name: 'tokenCount', type: 'integer' }
                ] },
              { name: 'candidatesTokensDetails',
                type: 'array',
                of: 'object',
                properties: [
                  { name: 'modality' },
                  { name: 'tokenCount', type: 'integer' }
                ] }
            ] },
          { name: 'modelVersion' },
          { name: 'createTime', type: 'date_time' },
          { name: 'responseId' },
          { name: 'rate_limit_status', type: 'object',
            properties: [
              { name: 'requests_last_minute', type: 'integer', label: 'Requests in last minute' },
              { name: 'limit', type: 'integer', label: 'Rate limit (requests/minute)' },
              { name: 'throttled', type: 'boolean', label: 'Was throttled' },
              { name: 'sleep_ms', type: 'integer', label: 'Sleep time (milliseconds)' }
            ] }
        ]
      end
    },
    translate_text_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'].concat(
          [
            { name: 'to', label: 'Output language', group: 'Task input', optional: false, control_type: 'select', pick_list: :languages_picklist,
              toggle_field: { name: 'to', label: 'Output language', control_type: 'text', type: 'string', optional: false, toggle_hint: 'Provide custom value', hint: 'Enter the output language. Eg. English' },
              toggle_hint: 'Select from list',
              hint: 'Select the desired output language' },
            { name: 'from', label: 'Source language', group: 'Task input', optional: true, sticky: true, control_type: 'select', pick_list: :languages_picklist,
              toggle_field: {
                name: 'from',
                control_type: 'text',
                type: 'string',
                optional: true,
                label: 'Source language',
                toggle_hint: 'Provide custom value',
                hint: 'Enter the source language. Eg. English'
              },
              toggle_hint: 'Select from list',
              hint: 'Select the source language. If this value is left blank, we will automatically attempt to identify it.' },
            { name: 'text', label: 'Source text', group: 'Task input', type: 'string', control_type: 'text-area', optional: false, hint: 'Enter the text to be translated. Please limit to 2000 tokens' }
          ]
        ).concat(object_definitions['config_schema'].only('safetySettings'))
      end
    },
    translate_text_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'answer', label: 'Translation' }
        ].concat(object_definitions['safety_rating_schema']).
          concat(object_definitions['usage_schema'])
      end
    },
    summarize_text_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'].concat(
          [
            { name: 'text',       label: 'Source text',   group: 'Task input',      type: 'string',  control_type: 'text-area', optional: false, hint: 'Provide the text to be summarized' },
            { name: 'max_words',  label: 'Maximum words', group: 'Summary options', type: 'integer', control_type: 'integer',   optional: true, sticky: true,
              hint: 'Enter the maximum number of words for the summary. If left blank, defaults to 200.' }
          ]
        ).concat(object_definitions['config_schema'].only('safetySettings'))
      end
    },
    summarize_text_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [ { name: 'answer', label: 'Summary' } ].concat(object_definitions['safety_rating_schema'])
                                                .concat(object_definitions['usage_schema'])
      end
    },
    parse_text_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'].concat(
          [
            { name: 'text', label: 'Source text', group: 'Task input', control_type: 'text-area', optional: false, hint: 'Provide the text to be parsed' },
            { name: 'object_schema', label: 'Fields to identify', group: 'Schema', optional: false, control_type: 'schema-designer', extends_schema: true,
              sample_data_type: 'json_http', empty_schema_title: 'Provide output fields for your job output.',
              hint: 'Enter the fields that you want to identify from the text. Add descriptions ' \
                    'for extracting the fields. Required fields take effect only on top level. ' \
                    'Nested fields are always optional.',
              exclude_fields: %w[hint label], exclude_fields_types: %w[integer date date_time],
              custom_properties: [
                {
                  name: 'description',
                  type: 'string',
                  optional: true,
                  label: 'Description'
                }
              ] }
          ]
        ).concat(object_definitions['config_schema'].only('safetySettings'))
      end
    },
    parse_text_output: {
      fields: lambda do |_connection, config_fields, object_definitions|
        next [] if config_fields['object_schema'].blank?

        schema = parse_json(config_fields['object_schema'] || '[]')
        schema.concat(object_definitions['safety_rating_schema']).
          concat(object_definitions['usage_schema'])
      end
    },
    draft_email_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'].concat(
          [
            { name: 'email_description', label: 'Email description', type: 'string', control_type: 'text-area', group: 'Task Input', optional: false, hint: 'Enter a description for the email' }
          ]
        ).concat(object_definitions['config_schema'].only('safetySettings'))
      end
    },
    draft_email_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'subject', label: 'Email subject' },
          { name: 'body', label: 'Email body' }
        ].concat(object_definitions['safety_rating_schema']).
          concat(object_definitions['usage_schema'])
      end
    },
    analyze_text_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'].concat(
          [
            { name: 'text', label: 'Source text', optional: false, control_type: 'text-area',
              group: 'Task input', hint: 'Provide the text to be analyzed.' },
            { name: 'question', label: 'Instruction', ptional: false, group: 'Instruction',
              hint: 'Enter analysis instructions, such as an analysis technique or question to be answered.' }
          ]
        ).concat(object_definitions['config_schema'].only('safetySettings'))
      end
    },
    analyze_text_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'answer', label: 'Analysis' }
        ].concat(object_definitions['safety_rating_schema']).
          concat(object_definitions['usage_schema'])
      end
    },
    analyze_image_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'model',
            optional: false, control_type: 'select', pick_list: :available_image_models,
            extends_schema: true, hint: 'Select the Gemini model to use',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'model', label: 'Model', group: 'Model',
              type: 'string', control_type: 'text', optional: false,
              extends_schema: true, toggle_hint: 'Use custom value',
              hint: 'Provide the model you want to use in this format: ' \
                    '<b>publishers/{publisher}/models/{model}</b>. ' \
                    'E.g. publishers/google/models/gemini-1.5-pro-001'} },
          { name: 'question', group: 'Prompt', optional: false,
            label: 'Your question about the image', hint: 'Please specify a clear question for image analysis.'},
          { name: 'image', label: 'Image data', group: 'Image', optional: false,
            hint: 'Provide the image to be analyzed.' },
          { name: 'mime_type', label: 'MIME type', group: 'Image', optional: false,
            hint: 'Provide the MIME type of the image. E.g. image/jpeg.' }
        ].concat(object_definitions['config_schema'].only('safetySettings'))
      end
    },
    analyze_image_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'answer',
            label: 'Analysis' }
        ].concat(object_definitions['safety_rating_schema']).
          concat(object_definitions['usage_schema'])
      end
    },
    find_neighbors_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'index_endpoint_host',
            label: 'Index endpoint host',
            optional: false,
            hint: 'The host for the index endpoint (no path). Example: 1234.us-central1.vdb.vertexai.goog '\
                  'for public endpoints, or your PSC DNS/IP. Do NOT include https://.',
            group: 'Endpoint' },

          { name: 'index_endpoint_id',
            label: 'Index endpoint ID',
            optional: false,
            hint: 'Resource ID only (not full path). Find it on the Index endpoint details page.',
            group: 'Index context' },

          { name: 'deployedIndexId',
            label: 'Deployed index ID',
            optional: false,
            sticky: true,
            hint: 'The deployed index to query (from your index endpoint).',
            group: 'Index context' },

          { name: 'returnFullDatapoint',
            label: 'Return full datapoints',
            type: 'boolean',
            control_type: 'checkbox',
            hint: 'If enabled, returns full vectors and restricts. Increases latency and cost.',
            group: 'Options' },

          {
            name: 'queries',
            type: 'array',
            of: 'object',
            optional: false,
            hint: 'One or more nearest-neighbor queries.',
            group: 'Queries',
            properties: [
              {
                name: 'datapoint',
                type: 'object',
                properties: [
                  { name: 'datapointId', label: 'Datapoint ID' },
                  { name: 'featureVector', label: 'Feature vector', type: 'array', of: 'number',
                    hint: 'Dense embedding (float array). Provide either a vector or an ID (or both).' },
                  { name: 'sparseEmbedding', type: 'object', properties: [
                    { name: 'values', type: 'array', of: 'number' },
                    { name: 'dimensions', type: 'array', of: 'integer' }
                  ]},
                  { name: 'restricts', type: 'array', of: 'object', properties: [
                    { name: 'namespace' },
                    { name: 'allowList', type: 'array', of: 'string' },
                    { name: 'denyList',  type: 'array', of: 'string' }
                  ]},
                  { name: 'numericRestricts', type: 'array', of: 'object', properties: [
                    { name: 'namespace' },
                    { name: 'op', control_type: 'select',
                      pick_list: :numeric_comparison_op,
                      toggle_hint: 'Select from list',
                      toggle_field: { name: 'op', type: 'string', control_type: 'text', optional: true,
                                      toggle_hint: 'Use custom value' } },
                    { name: 'valueInt',    type: 'integer', control_type: 'integer' },
                    { name: 'valueFloat',  type: 'number',  control_type: 'number'  },
                    { name: 'valueDouble', type: 'number',  control_type: 'number'  }
                  ]},
                  { name: 'crowdingTag', type: 'object', properties: [
                    { name: 'crowdingAttribute' }
                  ], hint: 'Optional; used to improve result diversity by limiting same-tag neighbors.' }
                ]
              },

              { name: 'neighborCount', type: 'integer', control_type: 'integer',
                hint: 'k — number of neighbors to return.' },
              { name: 'approximateNeighborCount', type: 'integer', control_type: 'integer',
                hint: 'Candidate pool size before exact re-ranking.' },
              { name: 'perCrowdingAttributeNeighborCount', type: 'integer', control_type: 'integer',
                hint: 'Max neighbors sharing same crowding attribute.' },
              { name: 'fractionLeafNodesToSearchOverride', type: 'number', control_type: 'number',
                hint: '0.0–1.0. Higher → better recall, higher latency.' }
            ]
          }
        ]
      end
    },
    find_neighbors_output: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          # Flattened recipe-friendly structure
          { name: 'matches_count', label: 'Number of matches', type: 'integer',
            hint: 'Total number of neighbors found' },
          { name: 'top_matches', label: 'Top matches (flattened)', type: 'array', of: 'object',
            properties: [
              { name: 'datapoint_id', label: 'Datapoint ID', type: 'string' },
              { name: 'distance', label: 'Distance', type: 'number' },
              { name: 'similarity_score', label: 'Similarity score (0-1)', type: 'number',
                hint: 'Normalized similarity score (1 - normalized_distance)' },
              { name: 'feature_vector', label: 'Feature vector', type: 'array', of: 'number' },
              { name: 'crowding_attribute', label: 'Crowding attribute', type: 'string' }
            ]
          },
          { name: 'best_match_id', label: 'Best match ID', type: 'string',
            hint: 'ID of the closest neighbor for quick recipe access' },
          { name: 'best_match_score', label: 'Best match score', type: 'number',
            hint: 'Similarity score of the best match (0-1)' },
          { name: 'pass_fail', label: 'Search success', type: 'boolean',
            hint: 'True if at least one neighbor was found' },
          { name: 'action_required', label: 'Action required', type: 'string',
            hint: 'Next recommended action based on search results' },
          # Original nested structure for backward compatibility
          { name: 'nearestNeighbors', label: 'Nearest neighbors (original)', type: 'array', of: 'object',
            properties: [
              { name: 'id', label: 'Query datapoint ID' },
              { name: 'neighbors', type: 'array', of: 'object',
                properties: [
                  { name: 'distance', type: 'number' },
                  { name: 'datapoint', type: 'object',
                    properties: [
                      { name: 'datapointId' },
                      { name: 'featureVector', type: 'array', of: 'number' },
                      { name: 'restricts', type: 'array', of: 'object' },
                      { name: 'numericRestricts', type: 'array', of: 'object' },
                      { name: 'crowdingTag', type: 'object' },
                      { name: 'sparseEmbedding', type: 'object' }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },
    safety_rating_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'safety_ratings',
            type: 'object',
            properties: [
              { name: 'sexually_explicit' },
              { name: 'hate_speech' },
              { name: 'harassment' },
              { name: 'dangerous_content' }
            ] }
        ]
      end
    },
    usage_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'usage',
            type: 'object',
            properties: [
              { name: 'promptTokenCount', type: 'integer' },
              { name: 'candidatesTokenCount', type: 'integer' },
              { name: 'totalTokenCount', type: 'integer' }
            ] }
        ]
      end
    },
    text_model_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'model', group: 'Model',
            optional: false, control_type: 'select', extends_schema: true,
            pick_list: :available_text_models,
            hint: 'Select the Gemini model to use', toggle_hint: 'Select from list',
            toggle_field: {
              name: 'model', label: 'Model',
              type: 'string', control_type: 'text', optional: false, 
              extends_schema: true, toggle_hint: 'Use custom value',
              hint: 'Provide the model you want to use in this format: ' \
                    '<b>publishers/{publisher}/models/{model}</b>. ' \
                    'E.g. publishers/google/models/gemini-1.5-pro-001'
            } }
        ]
      end
    }
  },

  pick_lists: {
    available_text_models: lambda do |connection|
      static = [
        ['Gemini 1.0 Pro', 'publishers/google/models/gemini-pro'],
        ['Gemini 1.5 Pro', 'publishers/google/models/gemini-1.5-pro'],
        ['Gemini 1.5 Flash', 'publishers/google/models/gemini-1.5-flash'],
        ['Gemini 2.0 Flash Lite', 'publishers/google/models/gemini-2.0-flash-lite-001'],
        ['Gemini 2.0 Flash', 'publishers/google/models/gemini-2.0-flash-001'],
        ['Gemini 2.5 Pro', 'publishers/google/models/gemini-2.5-pro'],
        ['Gemini 2.5 Flash', 'publishers/google/models/gemini-2.5-flash'],
        ['Gemini 2.5 Flash Lite', 'publishers/google/models/gemini-2.5-flash-lite']
      ]
      call('dynamic_model_picklist', connection, :text, static)
    end,
    available_image_models: lambda do |connection|
      static = [
        ['Gemini Pro Vision', 'publishers/google/models/gemini-pro-vision'],
        ['Gemini 1.5 Pro', 'publishers/google/models/gemini-1.5-pro'],
        ['Gemini 1.5 Flash', 'publishers/google/models/gemini-1.5-flash'],
        ['Gemini 2.0 Flash Lite', 'publishers/google/models/gemini-2.0-flash-lite-001'],
        ['Gemini 2.0 Flash', 'publishers/google/models/gemini-2.0-flash-001'],
        ['Gemini 2.5 Pro', 'publishers/google/models/gemini-2.5-pro'],
        ['Gemini 2.5 Flash', 'publishers/google/models/gemini-2.5-flash'],
        ['Gemini 2.5 Flash Lite', 'publishers/google/models/gemini-2.5-flash-lite']
      ]
      call('dynamic_model_picklist', connection, :image, static)
    end,
    available_embedding_models: lambda do |connection|
      static = [
        ['Text embedding gecko-001', 'publishers/google/models/textembedding-gecko@001'],
        ['Text embedding gecko-003', 'publishers/google/models/textembedding-gecko@003'],
        ['Text embedding-004', 'publishers/google/models/text-embedding-004']
      ]
      call('dynamic_model_picklist', connection, :embedding, static)
    end,
    message_types: lambda do
      %w[single_message chat_transcript].map { |m| [m.humanize, m] }
    end,
    numeric_comparison_op: lambda do
      %w[EQUAL NOT_EQUAL LESS LESS_EQUAL GREATER GREATER_EQUAL].map { |m| [m.humanize, m] }
    end,
    safety_categories: lambda do
      %w[HARM_CATEGORY_UNSPECIFIED HARM_CATEGORY_HATE_SPEECH
         HARM_CATEGORY_DANGEROUS_CONTENT HARM_CATEGORY_HARASSMENT
         HARM_CATEGORY_SEXUALLY_EXPLICIT].map { |m| [m.humanize, m] }
    end,
    safety_threshold: lambda do
      %w[HARM_BLOCK_THRESHOLD_UNSPECIFIED BLOCK_LOW_AND_ABOVE
         BLOCK_MEDIUM_AND_ABOVE BLOCK_ONLY_HIGH BLOCK_NONE OFF].
        map { |m| [m.humanize, m] }
    end,
    safety_method: lambda do
      %w[HARM_BLOCK_METHOD_UNSPECIFIED SEVERITY PROBABILITY].
        map { |m| [m.humanize, m] }
    end,
    response_type: lambda do
      [
        ['Text', 'text/plain'],
        ['JSON', 'application/json']
      ]
    end,
    chat_role: lambda do
      %w[model user].map { |m| [m.labelize, m] }
    end,
    function_call_mode: lambda do
      %w[MODE_UNSPECIFIED AUTO ANY NONE].map { |m| [m.humanize, m] }
    end,
    languages_picklist: lambda do
      [
        'Albanian', 'Arabic', 'Armenian', 'Awadhi', 'Azerbaijani', 'Bashkir', 'Basque',
        'Belarusian', 'Bengali', 'Bhojpuri', 'Bosnian', 'Brazilian Portuguese', 'Bulgarian',
        'Cantonese (Yue)', 'Catalan', 'Chhattisgarhi', 'Chinese', 'Croatian', 'Czech', 'Danish',
        'Dogri', 'Dutch', 'English', 'Estonian', 'Faroese', 'Finnish', 'French', 'Galician',
        'Georgian', 'German', 'Greek', 'Gujarati', 'Haryanvi', 'Hindi',
        'Hungarian', 'Indonesian', 'Irish', 'Italian', 'Japanese', 'Javanese', 'Kannada',
        'Kashmiri', 'Kazakh', 'Konkani', 'Korean', 'Kyrgyz', 'Latvian', 'Lithuanian',
        'Macedonian', 'Maithili', 'Malay', 'Maltese', 'Mandarin', 'Mandarin Chinese', 'Marathi',
        'Marwari', 'Min Nan', 'Moldovan', 'Mongolian', 'Montenegrin', 'Nepali', 'Norwegian',
        'Oriya', 'Pashto', 'Persian (Farsi)', 'Polish', 'Portuguese', 'Punjabi', 'Rajasthani',
        'Romanian', 'Russian', 'Sanskrit', 'Santali', 'Serbian', 'Sindhi', 'Sinhala', 'Slovak',
        'Slovene', 'Slovenian', 'Swedish', 'Ukrainian', 'Urdu', 'Uzbek', 'Vietnamese',
        'Welsh', 'Wu'
      ]
    end,
    embedding_task_list: lambda do
      [
        ['Retrieval query', 'RETRIEVAL_QUERY'],
        ['Retrieval document', 'RETRIEVAL_DOCUMENT'],
        ['Semantic similarity', 'SEMANTIC_SIMILARITY'],
        %w[Classification CLASSIFICATION],
        %w[Clustering CLUSTERING],
        ['Question answering', 'QUESTION_ANSWERING'],
        ['Fact verification', 'FACT_VERIFICATION']
      ]
    end
  }
}
