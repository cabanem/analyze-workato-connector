{
  title: 'Vertex AI',
  version: '0.7.0',
  
  # ============================================
  # CONNECTION & AUTHENTICATION
  # ============================================
  connection: {
    fields: [
      # Authentication type
      { name: 'auth_type', label: 'Authentication type', group: 'Authentication', control_type: 'select', default: 'custom',
        optional: false, extends_schema: true, hint: 'Select the authentication type for connecting to Google Vertex AI.',
        options: [ ['Service account (JWT)', 'custom'], ['OAuth 2.0 (Auth code)', 'oauth2'] ]},
      # Google Cloud Configuration
      { name: 'project', label: 'Project ID', group: 'Google Cloud Platform', optional: false },
      { name: 'region',  label: 'Region',     group: 'Google Cloud Platform', optional: false, control_type: 'select', 
        options: [
          ['Global', 'global'],
          ['US central 1', 'us-central1'],
          ['US east 1', 'us-east1'],
          ['US east 4', 'us-east4'],
          ['US east 5', 'us-east5'],
          ['US west 1', 'us-west1'],
          ['US west 4', 'us-west4'],
          ['US south 1', 'us-south1'],
        ],
        hint: 'Vertex AI region for model execution.',
        toggle_hint: 'Select from list',
        toggle_field: {
          name: 'region',
          label: 'Region',
          type: 'string',
          control_type: 'text',
          optional: false,
          toggle_hint: 'Use custom value',
          hint: "See Vertex AI locations docs for allowed regions."
        }
      },
      { name: 'version', label: 'API version', group: 'Google Cloud Platform', optional: false, default: 'v1', hint: 'e.g. v1beta1' },
      
      # Optional Configurations
      { name: 'vector_search_endpoint', label: 'Vector Search Endpoint', optional: true, hint: 'Public Vector Search domain host for queries' },
      
      # Default Behaviors
      { name: 'default_model', label: 'Default Model', control_type: 'select',
        options: [
          ['Gemini 1.5 Flash', 'gemini-1.5-flash'],
          ['Gemini 1.5 Pro',   'gemini-1.5-pro'],
          ['Text Embedding 004', 'text-embedding-004'],
          ['Text Embedding Gecko', 'textembedding-gecko']
        ],
        optional: true },
      { name: 'optimization_mode', label: 'Optimization Mode', control_type: 'select',
        options: [['Balanced', 'balanced'], ['Cost', 'cost'], ['Performance', 'performance']],
        default: 'balanced' },
      { name: 'enable_caching', label: 'Enable Response Caching', control_type: 'checkbox', default: true },
      { name: 'enable_logging', label: 'Enable Debug Logging', control_type: 'checkbox', default: false }
    ],
    
    authorization: {
      type: 'multi',
      selected: lambda do |connection|
        connection['auth_type'] || 'custom'
      end,
      identity: lambda do |connection|
        selected = connection['auth_type'] || 'custom'
        if selected == 'oauth2'
          begin
            info = call('http_request',
              connection,
              method: 'GET',
              url: 'https://openidconnect.googleapis.com/v1/userinfo',
              headers: {}, # Authorization comes from apply()
              retry_config: { max_attempts: 2, backoff: 0.5, retry_on: [429,500,502,503,504] }
            )
            email = info['email'] || '(no email)'
            name  = info['name']
            sub   = info['sub']
            [name, email, sub].compact.join(' / ')
          rescue
            'OAuth2 (Google) – identity unavailable'
          end
        else
          connection['service_account_email']
        end
      end,
      options: {
        oauth2: {
          type: 'oauth2',
          fields: [
            { name: 'client_id', label: 'Client ID', group: 'OAuth 2.0', optional: false },
            { name: 'client_secret', label: 'Client Secret', group: 'OAuth 2.0', optional: false, control_type: 'password' },
            { name: 'oauth_refresh_token_ttl', label: 'Refresh token TTL (seconds)', group: 'OAuth 2.0', type: 'integer', optional: true,
              hint: 'Used only if Google does not return refresh_token_expires_in; enables background refresh.' }
          ],
          # AUTH URL
          authorization_url: lambda do |connection|
            scopes = [
              'https://www.googleapis.com/auth/cloud-platform',
              'openid', 'email', 'profile' # needed for /userinfo claims
            ].join(' ')

            params = {
              client_id: connection['client_id'],
              response_type: 'code',
              scope: scopes,
              access_type: 'offline',
              include_granted_scopes: 'true',
              prompt: 'consent'
            }

            qs = call('to_query', params)
            "https://accounts.google.com/o/oauth2/v2/auth?#{qs}"
          end,
          # ACQUIRE
          acquire: lambda do |connection, auth_code|
            resp = call('http_request',
              connection,
              method: 'POST',
              url: 'https://oauth2.googleapis.com/token',
              payload: {
                client_id: connection['client_id'],
                client_secret: connection['client_secret'],
                grant_type: 'authorization_code',
                code: auth_code,
                redirect_uri: 'https://www.workato.com/oauth/callback'
              },
              headers: { },                 # no X-Goog-User-Project on token exchange
              request_format: 'form',
              retry_config: { max_attempts: 3, backoff: 1.0, retry_on: [429,500,502,503,504] }
            )

            body = resp # JSON Hash
            ttl = body['refresh_token_expires_in'] || connection['oauth_refresh_token_ttl']

            [
              {
                access_token: body['access_token'],
                refresh_token: body['refresh_token'],
                refresh_token_expires_in: ttl
              },
              nil,
              {}
            ]
          end,

          # REFRESH
          refresh: lambda do |connection, refresh_token|
            resp = call('http_request',
              connection,
              method: 'POST',
              url: 'https://oauth2.googleapis.com/token',
              payload: {
                client_id: connection['client_id'],
                client_secret: connection['client_secret'],
                grant_type: 'refresh_token',
                refresh_token: refresh_token
              },
              headers: {},
              request_format: 'form',
              retry_config: { max_attempts: 3, backoff: 1.0, retry_on: [429,500,502,503,504] }
            )

            {
              access_token: resp['access_token'],
              refresh_token: resp['refresh_token'],
              refresh_token_expires_in: resp['refresh_token_expires_in'] || connection['oauth_refresh_token_ttl']
            }.compact
          end,

          # APPLY
          apply: lambda do |_connection, access_token|
            headers(Authorization: "Bearer #{access_token}")
          end
        },
        custom: {
          type: 'custom_auth',
          fields: [
            { name: 'service_account_email', label: 'Service Account Email', group: 'Service Account', optional: false },
            { name: 'client_id', label: 'Client ID', group: 'Service Account', optional: false },
            { name: 'private_key_id', label: 'Private Key ID', group: 'Service Account', optional: false },
            { name: 'private_key', label: 'Private Key', group: 'Service Account', optional: false, multiline: true, control_type: 'password' }
          ],
          acquire: lambda do |connection|
            issued_at = Time.now.to_i
            jwt_body_claim = {
              'iat' => issued_at,
              'exp' => issued_at + 3600,
              'aud' => 'https://oauth2.googleapis.com/token',
              'iss' => connection['service_account_email'],
              'scope' => 'https://www.googleapis.com/auth/cloud-platform'
            }
            private_key = connection['private_key'].to_s.gsub('\\n', "\n")
            jwt_token   = workato.jwt_encode(jwt_body_claim, private_key, 'RS256', kid: connection['private_key_id'])

            resp = call('http_request',
              connection,
              method: 'POST',
              url: 'https://oauth2.googleapis.com/token',
              payload: {
                grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                assertion: jwt_token
              },
              headers: {},
              request_format: 'form',
              retry_config: { max_attempts: 3, backoff: 1.0, retry_on: [429,500,502,503,504] }
            )

            { access_token: resp['access_token'], expires_at: (Time.now + resp['expires_in'].to_i).iso8601 }
          end,
          refresh_on: [401],
          apply: lambda do |connection|
            headers(Authorization: "Bearer #{connection['access_token']}")
          end
        }
      }
    },
    
    base_uri: lambda do |connection|
      ver = connection['version']
      reg = connection['region']

      version = (ver && !ver.to_s.strip.empty?) ? ver.to_s : 'v1'
      region = (reg && !reg.to_s.strip.empty?) ? reg.to_s : 'us-east4'

      host = (region == 'global') ? 'aiplatform.googleapis.com' : "#{region}-aiplatform.googleapis.com"
      "https://#{host}/#{version}/"
    end
  },
  
  test: lambda do |connection|
    project = connection['project']
    region  = connection['region']

    # 1) Token + API enablement (global catalog)
    call('list_publisher_models', connection) # raises normalized errors

    # 2) Regional reachability / permissions
    parent = "projects/#{project}/locations/#{region}"
    call('http_request',
      connection,
      method:  'GET',
      url:     "#{parent}/endpoints",
      headers: call('build_headers', connection)
    )

    true
  rescue => e
    # Keep the normalized, compact message as‑is
    error(e.message)
  end,

  # ============================================
  # ACTIONS
  # ============================================
  # Listed alphabetically within each subsection.
  actions: {

    # ------------------------------------------
    # CORE
    # ------------------------------------------
    # Batch Operation Action
    batch_operation: {
      title: 'UNIVERSAL - Batch AI Operation',
      # CONFIG
      config_fields: [
        { name: 'behavior', label: 'Operation Type', control_type: 'select', pick_list: 'batchable_behaviors', optional: false },
        { name: 'batch_strategy', label: 'Batch Strategy', control_type: 'select', default: 'count', options: [['By Count', 'count'], ['By Token Limit', 'tokens']] },
        { name: 'advanced_config', label: 'Show Advanced Configuration', control_type: 'checkbox', extends_schema: true, optional: true, default: false }
      ],
      # INPUT
      input_fields: lambda do |_obj_defs, _connection, config_fields|
        cfg = config_fields.is_a?(Hash) ? config_fields : {}
        fields = [
          { name: 'items', type: 'array', of: 'object', properties: [
              { name: 'text', label: 'Text', optional: false },
              { name: 'task_type', label: 'Task Type', control_type: 'select', pick_list: 'embedding_tasks' }
          ]}
        ]

        if cfg['batch_strategy'] == 'tokens'
          fields << { name: 'token_ceiling', label: 'Token ceiling per batch (approx)',
                      type: 'integer', optional: false,
                      hint: 'Approximation: tokens ≈ characters/4' }
        else
          fields << { name: 'batch_size', type: 'integer', default: 10, hint: 'Items per batch' }
        end

        if cfg['advanced_config']
          fields += [
            { name: 'max_items_per_batch', label: 'Max items per batch', type: 'integer', default: 100, group: 'Advanced',
              hint: 'Guardrail applied to both strategies' },
            { name: 'max_body_bytes', label: 'Approx max body size (bytes)', type: 'integer', default: 1000000, group: 'Advanced',
              hint: 'Guardrail; approximate JSON payload size' }
          ]
        end

        fields
      end,
      # EXECUTE
      execute: lambda do |connection, input, _in_schema, _out_schema, config_fields|
        behavior = config_fields['behavior']
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        inner = call('execute_batch_behavior',
          connection,
          behavior,
          call('deep_copy', input['items']), # don't mutate caller input
          input['batch_size'],
          config_fields['batch_strategy'],
          {
            'token_ceiling'       => input['token_ceiling'],
            'max_items_per_batch' => input['max_items_per_batch'],
            'max_body_bytes'      => input['max_body_bytes']
          }.compact
        )

        # Telemetry
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        envelope_trace = { 'correlation_id' => "#{Time.now.utc.to_i}-#{SecureRandom.hex(6)}", 'duration_ms' => duration_ms, 'attempt' => 1 }

        call('enrich_response',
          response: inner.merge('_trace' => envelope_trace),
          metadata: { 'operation' => "batch.#{behavior}", 'model' => 'n/a' }
        )
      end,
      # OUTPUT
      output_fields: lambda do |_obj, _conn, _cfg|
        call('telemetry_envelope_fields') + [
          { name: 'results', type: 'array', of: 'object' },
          { name: 'errors',  type: 'array', of: 'object', properties: [
            { name: 'batch', type: 'array', of: 'object' },
            { name: 'error' }
          ]},
          { name: 'total_processed', type: 'integer' },
          { name: 'total_errors', type: 'integer' }
        ]
      end,
      # SAMPLE
      sample_output: lambda do |_conn, cfg|
        op = cfg['behavior'] || 'unknown'
        base = {
          "success"   => true,
          "timestamp" => "2025-01-01T00:00:00Z",
          "metadata"  => { "operation" => "batch.#{op}", "model" => "n/a" },
          "trace"     => { "correlation_id" => "abc", "duration_ms" => 42, "attempt" => 1 },
          "results"   => [],
          "errors"    => [],
          "total_processed" => 0,
          "total_errors"    => 0
        }
        if op == 'text.embed'
          base.merge(
            "results"=>[
              { "embeddings"=>[[0.01,0.02],[0.03,0.04]] }
            ],
            "total_processed"=>2
          )
        else
          base
        end
      end
    },

    # Universal Action
    vertex_operation: {
      title: 'UNIVERSAL - Vertex AI Operation',
      # CONFIG
      config_fields: [
        { name: 'behavior', label: 'Operation Type', control_type: 'select', pick_list: 'available_behaviors', optional: false, extends_schema: true,
          hint: 'Select the AI operation to perform' },
        { name: 'model_mode', label: 'Model selection', group: 'Model & tuning', control_type: 'select',
          options: [
            ['Auto (use connection strategy)', 'auto'],
            ['Explicit (choose model below)', 'explicit'],
            ['Use connection default',        'connection'] ],
          default: 'auto', optional: false, sticky: true, extends_schema: true, # forces input_fields to re-render when changed
          hint: 'Switch to Explicit to pick an exact Vertex model for this step.'
        },
        { name: 'model',
          label: 'Model',
          group: 'Model & tuning',
          control_type: 'select',
          sticky: true,
          optional: true,
          extends_schema: true,
          ngIf: 'input.model_mode == "explicit"',
          pick_list: 'models_dynamic_for_behavior', 
          pick_list_params: { behavior: 'behavior' },  # bind by field by NAME
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'model',
            label: 'Model (custom id)',
            type: 'string',
            control_type: 'text',
            optional: true,
            toggle_hint: 'Provide custom value'
          } },
        { name: 'lock_model_revision',
          label: 'Lock to latest numbered revision',
          control_type: 'checkbox',
          group: 'Model & tuning',
          ngIf: 'input.model_mode == "explicit"',
          hint: 'Resolves alias (e.g., gemini-1.5-pro) to highest numeric rev at runtime.' },
        { name: 'advanced_config', label: 'Show Advanced Configuration', control_type: 'checkbox', extends_schema: true, optional: true, default: false }
      ],
      # INPUT
      input_fields: lambda do |_obj_defs, _connection, config_fields|
        cfg = config_fields.is_a?(Hash) ? config_fields : {}
        behavior = cfg['behavior']
        behavior ? call('get_behavior_input_fields', behavior, cfg['advanced_config'], cfg) : []
      end,
      # OUTPUT
      output_fields: lambda do |_object_definitions, _connection, config_fields|
        cfg = config_fields.is_a?(Hash) ? config_fields : {}
        call('telemetry_envelope_fields') + (call('get_behavior_output_fields', cfg['behavior']) || [])
      end,
      # EXECUTE
      execute: lambda do |connection, input, _in_schema, _out_schema, config_fields|
        behavior     = config_fields['behavior']
        user_config  = call('extract_user_config', input, config_fields['advanced_config'], config_fields)
        safe_input   = call('deep_copy', input) # do NOT mutate Workato’s input

        # Leave advanced fields in safe_input; pipeline reads only what it needs
        call('execute_behavior', connection, behavior, safe_input, user_config)
      end,
      # SAMPLE
      sample_output: lambda do |_connection, config_fields|
        behavior = (config_fields.is_a?(Hash) ? config_fields : {})['behavior']
        case behavior
        when 'text.generate'
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"text.generate", "model"=>"gemini-1.5-flash" },
            "trace"=>{ "correlation_id"=>"abc", "duration_ms"=>42, "attempt"=>1 },
            "result"=>"Hello world." }
        when 'text.translate'
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"text.translate", "model"=>"gemini-1.5-flash" },
            "trace"=>{ "correlation_id"=>"abc", "duration_ms"=>42, "attempt"=>1 },
            "result"=>"Hola mundo.", "detected_language"=>"en" }
        when 'text.summarize'
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"text.summarize", "model"=>"gemini-1.5-flash" },
            "trace"=>{ "correlation_id"=>"abc", "duration_ms"=>42, "attempt"=>1 },
            "result"=>"Concise summary.", "word_count"=>2 }
        when 'text.classify'
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"text.classify", "model"=>"gemini-1.5-flash" },
            "trace"=>{ "correlation_id"=>"abc", "duration_ms"=>42, "attempt"=>1 },
            "category"=>"Support", "confidence"=>0.98 }
        when 'text.embed'
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"text.embed", "model"=>"text-embedding-004" },
            "trace"=>{ "correlation_id"=>"abc", "duration_ms"=>42, "attempt"=>1 },
            "embeddings"=>[[0.01,0.02,0.03]] }
        when 'multimodal.analyze'
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"multimodal.analyze", "model"=>"gemini-1.5-pro" },
            "trace"=>{ "correlation_id"=>"abc", "duration_ms"=>42, "attempt"=>1 },
            "result"=>"The image shows a tabby cat on a desk." }
        else
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"unknown", "model"=>"gemini-1.5-flash" } }
        end
      end
    },

    # ------------------------------------------
    # THIN WRAPPERS
    # ------------------------------------------
    
    classify_text: {
      title: 'AI - Classify Text',
      description: 'Classify text into one of the provided categories',

      # CONFIG
      config_fields: [
        { name: 'model_mode', label: 'Model selection', group: 'Model & tuning', control_type: 'select', default: 'auto', optional: false,
          options: [
            ['Auto (use connection strategy)', 'auto'],
            ['Explicit (choose model below)', 'explicit'],
            ['Use connection default',        'connection'] ],
          sticky: true, extends_schema: true, # forces input_fields to re-render when changed
          hint: 'Switch to Explicit to pick an exact Vertex model for this step.'
        },
        { name: 'model',
          label: 'Model',
          group: 'Model & tuning',
          control_type: 'select',
          sticky: true,
          optional: true,
          extends_schema: true,
          ngIf: 'input.model_mode == "explicit"',
          pick_list: 'models_generation_dynamic',
          toggle_hint: 'Select from list',
          toggle_field: { name: 'model', label: 'Model (custom id)', type: 'string', control_type: 'text', optional: true, toggle_hint: 'Provide custom value' }},
        { name: 'lock_model_revision', label: 'Lock to latest numbered revision', control_type: 'checkbox', group: 'Model & tuning', ngIf: 'input.model_mode == "explicit"' },
        { name: 'advanced_config', label: 'Show Advanced Configuration', control_type: 'checkbox', extends_schema: true, optional: true, default: false }
      ],

      # INPUT
      input_fields: lambda do |_obj_defs, _connection, config_fields|
        cfg = config_fields.is_a?(Hash) ? config_fields : {}
        call('get_behavior_input_fields', 'text.classify', cfg['advanced_config'], cfg)
      end,

      # OUTPUT
      output_fields: lambda do |_obj_defs, _connection, _cfg|
        call('telemetry_envelope_fields') + call('get_behavior_output_fields', 'text.classify')
      end,

      # EXECUTE
      execute: lambda do |connection, input, _in_schema, _out_schema, config_fields|
        user_cfg = call('extract_user_config', input, config_fields['advanced_config'], config_fields)
        safe     = call('deep_copy', input) # never mutate Workato’s input
        call('execute_behavior', connection, 'text.classify', safe, user_cfg)
      end,

      # SAMPLE 
      sample_output: lambda do |_connection, _cfg|
        {
          "success"   => true,
          "timestamp" => Time.now.utc.iso8601,
          "metadata"  => { "operation" => "text.classify", "model" => "gemini-1.5-flash-002" },
          "trace"     => { "correlation_id" => "abc", "duration_ms" => 42, "attempt" => 1 },
          "category"  => "Support",
          "confidence"=> 0.98
        }
      end
    },

    find_neighbors: {
      title: 'VECTOR SEARCH - Find nearest neighbors',
      description: 'Query a deployed Vector Search index',
      # INPUT
      input_fields: lambda do |_obj_defs, _connection, _cfg|
        call('get_behavior_input_fields', 'vector.find_neighbors', true)
      end,
      # OUTPUT
      output_fields: lambda do |_obj_defs, _connection, _cfg|
        call('telemetry_envelope_fields') + call('get_behavior_output_fields', 'vector.find_neighbors')
      end,
      # EXECUTE
      execute: lambda do |connection, input, _in_schema, _out_schema, _cfg|
        call('execute_behavior', connection, 'vector.find_neighbors', call('deep_copy', input))
      end
    },

    generate_embeddings: {
      title: 'VECTOR SEARCH - Generate embeddings',
      description: 'Create dense embeddings for text',
      # CONFIG
      config_fields: [
        { name: 'model_mode', label: 'Model selection', group: 'Model & tuning', control_type: 'select', default: 'auto', optional: false,
          options: [
            ['Auto (use connection strategy)', 'auto'],
            ['Explicit (choose model below)', 'explicit'],
            ['Use connection default',        'connection'] ],
          sticky: true, extends_schema: true, # forces input_fields to re-render when changed
          hint: 'Switch to Explicit to pick an exact Vertex model for this step.'
        },
        { name: 'model',
          label: 'Model',
          group: 'Model & tuning',
          control_type: 'select',
          sticky: true,
          optional: true,
          extends_schema: true,
          ngIf: 'input.model_mode == "explicit"',
          pick_list: 'models_embedding_dynamic',
          toggle_hint: 'Select from list',
          toggle_field: { name: 'model', label: 'Model (custom id)', type: 'string', control_type: 'text', optional: true, toggle_hint: 'Provide custom value' } },
        { name: 'lock_model_revision', label: 'Lock to latest numbered revision', control_type: 'checkbox', group: 'Model & tuning', ngIf: 'input.model_mode == "explicit"' },
        { name: 'advanced_config', label: 'Show Advanced Configuration', control_type: 'checkbox', extends_schema: true, optional: true, default: false }
      ],
      # INPUT
      input_fields: lambda do |_obj_defs, _connection, config_fields|
        cfg = config_fields.is_a?(Hash) ? config_fields : {}
        call('get_behavior_input_fields', 'text.embed', cfg['advanced_config'], cfg)
      end,
      # OUTPUT
      output_fields: lambda do |_obj_defs, _connection, _cfg|
        call('telemetry_envelope_fields') + [
          { name: 'embeddings', type: 'array', of: 'array' }
        ]
      end,
      # EXECUTE
      execute: lambda do |connection, input, _in_schema, _out_schema, config_fields|
        user_cfg = call('extract_user_config', input, config_fields['advanced_config'], config_fields)
        safe     = call('deep_copy', input)
        call('execute_behavior', connection, 'text.embed', safe, user_cfg)
      end
    },
    
    generate_text: {
      title: 'AI - Generate Text',
      description: 'Gemini text generation',

      # CONFIG
      config_fields: [
        { name: 'model_mode', label: 'Model selection', group: 'Model & tuning', control_type: 'select', default: 'auto', optional: false,
          options: [
            ['Auto (use connection strategy)', 'auto'],
            ['Explicit (choose model below)', 'explicit'],
            ['Use connection default',        'connection'] ],
          sticky: true, extends_schema: true, hint: 'Switch to Explicit to pick an exact Vertex model for this step.'
        },
        { name: 'model',
          label: 'Model',
          group: 'Model & tuning',
          control_type: 'select',
          sticky: true,
          optional: true,
          extends_schema: true,
          ngIf: 'input.model_mode == "explicit"',
          pick_list: 'models_generation_dynamic',
          toggle_hint: 'Select from list',
          toggle_field: { name: 'model', label: 'Model (custom id)', type: 'string', control_type: 'text', optional: true, toggle_hint: 'Provide custom value' } },
        { name: 'lock_model_revision', label: 'Lock to latest numbered revision', control_type: 'checkbox', group: 'Model & tuning', ngIf: 'input.model_mode == "explicit"' },
        { name: 'advanced_config', label: 'Show Advanced Configuration', control_type: 'checkbox', extends_schema: true, optional: true, default: false }
      ],
      # INPUT
      input_fields: lambda do |_obj_defs, _connection, config_fields|
        cfg = config_fields.is_a?(Hash) ? config_fields : {}
        call('get_behavior_input_fields', 'text.generate', cfg['advanced_config'], cfg)
      end,
      # OUTPUT
      output_fields: lambda do |_obj_defs, _connection, _cfg|
        call('telemetry_envelope_fields') + call('get_behavior_output_fields', 'text.generate')
      end,
      # EXECUTE
      execute: lambda do |connection, input, _in_schema, _out_schema, config_fields|
        user_cfg = call('extract_user_config', input, config_fields['advanced_config'], config_fields)
        safe_input = call('deep_copy', input)
        call('execute_behavior', connection, 'text.generate', safe_input, user_cfg)
      end,
      # SAMPLE OUT
      sample_output: lambda do |_connection, _cfg|
        {
          "success" => true, "timestamp" => Time.now.utc.iso8601,
          "metadata" => { "operation" => "text.generate", "model" => "gemini-1.5-flash-002" },
          "trace" => { "correlation_id" => "abc", "duration_ms" => 42, "attempt" => 1 },
          "result" => "Hello world."
        }
      end
    },

    upsert_index_datapoints: {
      title: 'VECTOR SEARCH - Upsert index datapoints',
      description: 'Add or update datapoints in a Vector Search index',
      # INPUT
      input_fields: lambda do |_obj_defs, _connection, _cfg|
        call('get_behavior_input_fields', 'vector.upsert_datapoints', true)
      end,
      # OUTPUT
      output_fields: lambda do |_obj_defs, _connection, _cfg|
        call('telemetry_envelope_fields') + call('get_behavior_output_fields', 'vector.upsert_datapoints')
      end,
      # EXECUTE
      execute: lambda do |connection, input, _in_schema, _out_schema, _cfg|
        call('execute_behavior', connection, 'vector.upsert_datapoints', call('deep_copy', input))
      end
    }
  },

  # ============================================
  # METHODS - LAYERED ARCHITECTURE
  # ============================================
  methods: {
    # ============================================
    # LAYER 1: CORE METHODS (Foundation)
    # ============================================
    
    # Payload Building
    build_payload: lambda do |template:, variables:, format:|
      case format
      
      # Direct
      when 'direct'
        variables
      
      # Template
      when 'template'
        result = template.dup
        variables.each { |k, v| result = result.gsub("{#{k}}", v.to_s) }
        result
      
      # Vertex prompt
      when 'vertex_prompt'
        payload = {
          'contents' => [{
            'role' => 'user',
            'parts' => [{ 'text' => call('apply_template', template, variables) }]
          }],
          'generationConfig' => call('build_generation_config', variables)
        }.compact

        # Always honor system instructions if provided (Vertex v1 supports this)
        sys = variables['system']
        if sys && !sys.to_s.strip.empty?
          payload['systemInstruction'] = { 'parts' => [{ 'text' => sys }] }
        end

        # Advanced safety (new) — supports both array and legacy hash
        if variables['safety_settings']
          payload['safetySettings'] = call('normalize_safety_settings', variables['safety_settings'])
        end

        payload['labels'] = variables['labels'] if variables['labels']
        payload

      # Embedding
      when 'embedding'
        body = {
          'instances' => variables['texts'].map { |text|
            {
              'content'   => text,
              'task_type' => variables['task_type'] || 'RETRIEVAL_DOCUMENT',
              'title'     => variables['title']
            }.compact
          }
        }
        params = {}
        params['autoTruncate']          = variables['auto_truncate'] unless variables['auto_truncate'].nil?
        params['outputDimensionality']  = variables['output_dimensionality'] if variables['output_dimensionality']
        body['parameters'] = params unless params.empty? 
        body

      when 'find_neighbors'
        queries = Array(variables['queries']).map do |q|
          dp =
            if q['feature_vector']
              { 'feature_vector' => Array(q['feature_vector']).map(&:to_f) }
            elsif q['vector'] # alias
              { 'feature_vector' => Array(q['vector']).map(&:to_f) }
            elsif q['datapoint_id']
              { 'datapoint_id' => q['datapoint_id'] }
            else
              {}
            end
          {
            'datapoint'        => dp,
            'neighbor_count'   => (q['neighbor_count'] || variables['neighbor_count'] || 10).to_i,
            'restricts'        => q['restricts'],
            'numeric_restricts'=> q['numeric_restricts']
          }.compact
        end

        {
          'deployed_index_id'     => variables['deployed_index_id'],
          'queries'               => queries,
          'return_full_datapoint' => variables['return_full_datapoint']
        }.compact

      when 'upsert_datapoints'
        {
          'datapoints' => Array(variables['datapoints']).map do |d|
            {
              'datapointId'      => d['datapoint_id'] || d['id'],
              'featureVector'    => Array(d['feature_vector'] || d['vector']).map(&:to_f),
              'sparseEmbedding'  => d['sparse_embedding'],
              'restricts'        => d['restricts'],
              'numericRestricts' => d['numeric_restricts'],
              'crowdingTag'      => d['crowding_tag'],
              'embeddingMetadata'=> d['embedding_metadata']
            }.compact
          end
        }

      # Multimodal
      when 'multimodal'
        parts = []
        parts << { 'text' => variables['text'] } if variables['text']
        if variables['images']
          variables['images'].each do |img|
            parts << { 'inLineData' => { 'mimeType' => img['mime_type'] || 'image/jpeg', 'data' => img['data'] } }
          end
        end

        payload = {
          'contents' => [{ 'role' => 'user', 'parts' => parts }],
          'generationConfig' => call('build_generation_config', variables)
        }

        if variables['safety_settings']
          payload['safetySettings'] = call('normalize_safety_settings', variables['safety_settings'])
        end

        payload
        
      else
        variables
      end
    end,
    
    # Response Enrichment
    enrich_response: lambda do |response:, metadata: {}|
      base  = response.is_a?(Hash) ? JSON.parse(JSON.dump(response)) : { 'result' => response }
      trace = base.delete('_trace')
      _http = base.delete('_http') # kept internal; not exposed

      # Preserve success if caller provided it; otherwise assume true
      success = base.key?('success') ? base['success'] : true

      # Build a uniform trace object (always present)
      trace_hash  = trace.is_a?(Hash) ? trace : {}
      final_trace = {
        'correlation_id' => trace_hash['correlation_id'] || SecureRandom.hex(8),
        'duration_ms'    => (trace_hash['duration_ms'] || 0).to_i,
        'attempt'        => (trace_hash['attempt'] || 1).to_i
      }
      final_trace['rate_limit'] = trace_hash['rate_limit'] if trace_hash['rate_limit']

      base.merge(
        'success'   => success,
        'timestamp' => base['timestamp'] || Time.now.utc.iso8601,
        'metadata'  => { 'operation' => metadata['operation'], 'model' => metadata['model'] }.compact,
        'trace'     => final_trace
      ).compact
    end,

    # Response Extraction
    extract_response: lambda do |data:, path: nil, format: 'raw'|
      case format
      # Raw data
      when 'raw' then data
      # Json field
      when 'json_field'
        return data unless path
        path.split('.').reduce(data) { |acc, seg| acc.is_a?(Array) && seg =~ /^\d+$/ ? acc[seg.to_i] : (acc || {})[seg] }
      # Vertex text
      when 'vertex_text'
        parts = data.dig('candidates', 0, 'content', 'parts') || []
        text  = parts.select { |p| p['text'] }.map { |p| p['text'] }.join
        text.empty? ? data.dig('predictions', 0, 'content').to_s : text
      # Vertex-flavored json
      when 'vertex_json'
        raw = (data.dig('candidates', 0, 'content', 'parts') || []).map { |p| p['text'] }.compact.join
        return {} if raw.nil? || raw.empty?
        m = raw.match(/```(?:json)?\s*(\{.*?\})\s*```/m) || raw.match(/\{.*\}/m)
        m ? (JSON.parse(m[1] || m[0]) rescue {}) : {}
      # Embeddings
      when 'embeddings'
        # text-embedding APIs return embeddings under predictions[].embeddings.values
        arr = (data['predictions'] || []).map { |p| p.dig('embeddings', 'values') || p['values'] }.compact
        arr
      else data
      end
    end,

    # HTTP Request Execution
    http_request: lambda do |connection, method:, url:, payload: nil, headers: {}, retry_config: {}, request_format: 'json'|
      max_attempts = (retry_config['max_attempts'] || retry_config['max_retries'] || 3).to_i
      base_backoff = (retry_config['backoff'] || 1.0).to_f
      retry_on     = Array(retry_config['retry_on'] || [408, 429, 500, 502, 503, 504]).map(&:to_i)
      do_not_retry = Array(retry_config['do_not_retry']).map(&:to_i)

      attempt = 0
      last_error = nil

      while attempt < max_attempts
        attempt += 1
        begin
          hdrs = (headers || {}).dup
          corr = hdrs['X-Correlation-Id'] ||= "#{Time.now.utc.to_i}-#{SecureRandom.hex(6)}"
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          last_error = nil

          req = case method.to_s.upcase
                when 'GET'    then get(url)
                when 'POST'   then post(url, payload)
                when 'PUT'    then put(url, payload)
                when 'DELETE' then delete(url)
                else error("Unsupported HTTP method: #{method}")
                end

          # Respect application/x-www-form-urlencoded when requested
          if request_format.to_s == 'form'
            hdrs['Content-Type'] ||= 'application/x-www-form-urlencoded'
            req = req.request_format_www_form_urlencoded
          end

          response =
            req.headers(hdrs)
              .after_error_response(/.*/) { |code, body, rheaders, message|
                 dur_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
                 err = call('normalize_http_error',
                            connection,
                            code: code, body: body, headers: (rheaders || {}),
                            message: message, url: url, corr_id: corr, attempt: attempt, duration_ms: dur_ms)
                 last_error = err
                 error(call('format_user_error', err))
               }
              .after_response { |code, body, rheaders|
                # Always return a Hash payload with HTTP metadata, even when the API returns a raw string/bytes.
                payload = body.is_a?(Hash) ? body : { 'raw' => body }
                payload['_http'] = { 'status' => code, 'headers' => rheaders }
                payload
              }

          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
          out = response.is_a?(Hash) ? JSON.parse(JSON.dump(response)) : { 'raw' => response }

          # Extract a useful Google/Vertex request id when present.
          hdrs_out = (out.dig('_http', 'headers') || {})
          rid = hdrs_out['x-request-id'] || hdrs_out['x-cloud-trace-context'] || hdrs_out['x-guploader-uploadid']

          out['_trace'] = {
            'correlation_id'    => corr,
            'duration_ms'       => duration_ms,
            'attempt'           => attempt,
            'http_status'       => out.dig('_http','status'),
            'remote_request_id' => rid
          }.compact

          return out

        rescue => _e
          code = last_error ? last_error['code'].to_i : 0
          retryable = last_error ? last_error['retryable'] : retry_on.include?(code)
          retryable &&= !do_not_retry.include?(code)

          # Break if not retryable or out of attempts
          break unless retryable && attempt < max_attempts

          # Retry-After (seconds) takes precedence when present
          delay =
            if last_error && last_error['retry_after_s'].to_i > 0
              last_error['retry_after_s'].to_i
            else
              # exp backoff with small jitter
              (base_backoff * (2 ** (attempt - 1))).to_f + rand * 0.25
            end

          sleep(delay)
        end
      end

      # Exhausted: bubble the last normalized message if present
      msg = last_error ? call('format_user_error', last_error) : 'HTTP request failed'
      error(msg)
    end,

    # Data Transformation
    transform_data: lambda do |input:, from_format:, to_format:, connection: nil|
      case "#{from_format}_to_#{to_format}"
      when 'url_to_base64'
        # Use centralized http_request for retries and telemetry
        resp = call('http_request', connection, method: 'GET', url: input, headers: {})
        raw  = resp['raw'] || resp.to_s
        raw.to_s.encode_base64
      when 'base64_to_bytes'
        input.decode_base64
      when 'language_code_to_name'
        languages = { 'en' => 'English', 'es' => 'Spanish', 'fr' => 'French' }
        languages[input] || input
      when 'categories_to_text'
        input.map { |c| "#{c['name']}: #{c['description']}" }.join("\n")
      when 'distance_to_similarity'
        1.0 - (input.to_f / 2.0)
      else
        input
      end
    end,
    
    # Input Validation
    validate_input: lambda do |data:, schema: [], constraints: []|
      errors = []
      
      # Schema validation
      schema.each do |field|
        field_name = field['name']
        field_value = data[field_name]
        
        # Required check
        if field['required'] && (field_value.nil? || field_value.to_s.empty?)
          errors << "#{field_name} is required"
        end
        
        # Length validation
        if field['max_length'] && field_value.to_s.length > field['max_length']
          errors << "#{field_name} exceeds maximum length of #{field['max_length']}"
        end
        
        # Pattern validation
        if field['pattern'] && field_value && !field_value.match?(Regexp.new(field['pattern']))
          errors << "#{field_name} format is invalid"
        end
      end
      
      # Constraint validation
      constraints.each do |constraint|
        ctype = (constraint['type'] || constraint[:type]).to_s

        case ctype
        when 'min_value'
          value = data[(constraint['field'] || constraint[:field]).to_s].to_f
          if value < constraint['value'].to_f
            errors << "#{constraint['field'] || constraint[:field]} must be at least #{constraint['value']}"
          end

        when 'max_items'
          field = (constraint['field'] || constraint[:field]).to_s
          items = data[field] || []
          if Array(items).size > constraint['value'].to_i
            errors << "#{field} cannot exceed #{constraint['value']} items"
          end

        # XOR/ONE-OF across fields (root or per-item scope)
        when 'xor', 'one_of'
          scope   = (constraint['scope'] || constraint[:scope]).to_s # e.g., 'queries[]' or ''
          fields  = Array(constraint['fields'] || constraint[:fields]).map(&:to_s)
          aliases = (constraint['aliases'] || constraint[:aliases] || {}) # { 'feature_vector' => ['vector'] }
          exactly_one = (ctype == 'xor') || (constraint['exactly_one'] == true)

          call('each_in_scope', data, scope).each do |ctx, label|
            count = 0
            fields.each do |f|
              keys = [f] + Array(aliases[f] || aliases[f.to_sym]).map(&:to_s)
              present = keys.any? { |k| call('value_present', ctx[k]) }
              count += 1 if present
            end

            if exactly_one
              if count != 1
                display = fields.map { |f|
                  al = Array(aliases[f] || aliases[f.to_sym])
                  al.any? ? "#{f} (alias: #{al.join(', ')})" : f
                }.join(', ')
                errors << "#{label}: exactly one of #{display} must be provided"
              end
            else
              if count < 1
                errors << "#{label}: at least one of #{fields.join(', ')} must be provided"
              end
            end
          end

        # Conditional required with root-level fallback and optional default
        # Example: each queries[].neighbor_count is optional if top-level neighbor_count is present,
        # or if a default is defined; else required.
        when 'fallback_required', 'conditional_required'
          scope    = (constraint['scope'] || constraint[:scope]).to_s       # e.g., 'queries[]'
          field    = (constraint['field'] || constraint[:field]).to_s       # e.g., 'neighbor_count'
          fallback = (constraint['fallback_to_root'] || constraint[:fallback_to_root]).to_s # e.g., 'neighbor_count'
          default_ok = constraint.key?('default_if_absent') || constraint.key?(:default_if_absent)

          root_has_fallback = fallback.empty? ? false : call('value_present', data[fallback])

          call('each_in_scope', data, scope).each do |ctx, label|
            item_has = call('value_present', ctx[field])
            unless item_has || root_has_fallback || default_ok
              if fallback.empty?
                errors << "#{label}.#{field} is required"
              else
                errors << "#{label}.#{field} is required when top-level #{fallback} is not provided"
              end
            end
          end

        else
          # unknown constraint type: ignore silently (forward-compatible)
        end
      end
      
      error(errors.join('; ')) if errors.any?
      true
    end,
    
    # Error Recovery
    with_resilience: lambda do |operation:, config: {}, task: {}, connection: nil, &blk|
      # Rate limiting (per-job) — always initialize and use a unique name
      rate_limit_info = nil
      if config['rate_limit']
        rate_limit_info = call('check_rate_limit', operation, config['rate_limit'])
      end

      circuit_key   = "circuit_#{operation}"
      circuit_state = call('memo_get', circuit_key) || { 'failures' => 0 }
      error("Circuit breaker open for #{operation}. Too many recent failures.") if circuit_state['failures'] >= 5

      begin
        result =
          if blk
            # Instrument the block path so trace is still present
            corr    = "#{Time.now.utc.to_i}-#{SecureRandom.hex(6)}"
            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            raw     = blk.call
            dur_ms  = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
            out     = raw.is_a?(Hash) ? JSON.parse(JSON.dump(raw)) : { 'result' => raw }
            out['_trace'] ||= {}
            out['_trace'].merge!({ 'correlation_id' => corr, 'duration_ms' => dur_ms, 'attempt' => 1 })
            out
          else
            error('with_resilience requires a task hash with url/method') unless task.is_a?(Hash) && task['url']

            call('http_request',
              connection,
              method:       (task['method'] || 'GET'),
              url:          task['url'],
              payload:      task['payload'],
              headers:      (task['headers'] || {}),
              retry_config: (task['retry_config'] || {})
            )
          end

        # Attach rate-limit counters to trace if present (guarded)
        if rate_limit_info && result.is_a?(Hash)
          result['_trace'] ||= {}
          result['_trace']['rate_limit'] = rate_limit_info
        end

        # Reset circuit on success
        call('memo_put', circuit_key, { 'failures' => 0 }, 300)
        result

      rescue => e
        circuit_state['failures'] += 1
        call('memo_put', circuit_key, circuit_state, 300)
        # Keep normalized messages intact; do not blanket-retry non-retryables here
        raise e
      end
    end,

    # ============================================
    # LAYER 2: UNIVERSAL PIPELINE
    # ============================================
    
    execute_pipeline: lambda do |connection, operation, input, config|
      # Don't mutate the input
      local = call('deep_copy', input)

      # 1. Validate
      if config['validate']
        call('validate_input',
          data:         local,
          schema:       config['validate']['schema'] || [],
          constraints:  config['validate']['constraints'] || []
        )
      end
      
      # 2. Transform input
      if config['transform_input']
        config['transform_input'].each do |field, transform|
          if local[field]
            local[field] = call('transform_data',
              input:        local[field],
              from_format:  transform['from'],
              to_format:    transform['to'],
              connection:   connection
            )
          end
        end
      end

      # -- Ensure selected model from ops config is visible to URL builder
      local['model'] ||= config['model']

      # 3. Build payload
      payload = if config['payload']
        call('build_payload',
          template:   config['payload']['template'] || '',
          variables:  local.merge('system' => config['payload']['system']),
          format:     config['payload']['format'] || 'direct'
        )
      else
        local
      end
      
      # 4. Build URL
      endpoint  = config['endpoint'] || {}
      url       = call('build_endpoint_url', connection, endpoint, local)
      
      # 5. Execute with resilience
      response = call('with_resilience',
        operation:  operation,
        config:     (config['resilience'] || {}),
        task: {
          'method'       => endpoint['method'] || 'POST',
          'url'          => url,
          'payload'      => payload,
          'headers'      => call('build_headers', connection),
          'retry_config' => (config.dig('resilience', 'retry') || {})
        },
        connection: connection
      )
      
      trace_from_response = (response.is_a?(Hash) ? response['_trace'] : nil)

      # 6. Extract response
      extracted = if config['extract']
        call('extract_response',
          data:   response,
          path:   config['extract']['path'],
          format: config['extract']['format'] || 'raw'
        )
      else
        response
      end

      # Preserve trace even if extracted is a primitive
      if trace_from_response
        if extracted.is_a?(Hash)
          extracted['_trace'] ||= {}
          extracted['_trace'].merge!(trace_from_response)
        else
          extracted = { 'result' => extracted, '_trace' => trace_from_response }
        end
      end
      
      # 7. Post-process
      if config['post_process']
        extracted = call(config['post_process'], extracted, local)
      end
      
      # 8. Enrich
      call('enrich_response',
        response: extracted,
        metadata: { 'operation' => operation, 'model' => config['model'] || local['model'] }
      )
    end,
    
    # ============================================
    # LAYER 3: BEHAVIOR & CONFIGURATION
    # ============================================
    
    # Behavior Registry - Catalog of capabilities
    behavior_registry: lambda do
      {
        # Text Operations
        'text.generate' => {
          description: 'Generate text from a prompt',
          capability: 'generation',
          supported_models: ['gemini-1.5-flash', 'gemini-1.5-pro'],
          features: ['streaming', 'caching'],
          config_template: {
            'payload' => {
              'format' => 'vertex_prompt',
              'template' => '{prompt}',
              'system' => nil
            },
            'endpoint' => {
              'path' => ':generateContent',
              'method' => 'POST'
            },
            'extract' => {
              'format' => 'vertex_text'
            }
          }
        },
        
        'text.translate' => {
          description: 'Translate text between languages',
          capability: 'generation',
          supported_models: ['gemini-1.5-flash', 'gemini-1.5-pro'],
          features: ['caching', 'batching'],
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'text', 'required' => true, 'max_length' => 10000 },
                { 'name' => 'target_language', 'required' => true }
              ]
            },
            'transform_input' => {
              'source_language' => { 'from' => 'language_code', 'to' => 'name' },
              'target_language' => { 'from' => 'language_code', 'to' => 'name' }
            },
            'payload' => {
              'format' => 'vertex_prompt',
              'template' => 'Translate the following text from {source_language} to {target_language}. Return only the translation:\n\n{text}',
              'system' => 'You are a professional translator. Maintain tone and context.'
            },
            'endpoint' => {
              'path' => ':generateContent',
              'method' => 'POST'
            },
            'extract' => {
              'format' => 'vertex_text'
            }
          },
          defaults: {
            'temperature' => 0.3,
            'max_tokens' => 2048
          }
        },
        
        'text.summarize' => {
          description: 'Summarize text content',
          capability: 'generation',
          supported_models: ['gemini-1.5-flash', 'gemini-1.5-pro'],
          features: ['caching'],
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'text', 'required' => true },
                { 'name' => 'max_words', 'required' => false }
              ]
            },
            'payload' => {
              'format' => 'vertex_prompt',
              'template' => 'Summarize the following text in {max_words} words:\n\n{text}',
              'system' => 'You are an expert at creating clear, concise summaries.'
            },
            'endpoint' => {
              'path' => ':generateContent'
            },
            'extract' => {
              'format' => 'vertex_text'
            },
            'post_process' => 'add_word_count'
          },
          defaults: {
            'temperature' => 0.5,
            'max_words' => 200
          }
        },
        
        'text.classify' => {
          description: 'Classify text into categories',
          capability: 'generation',
          supported_models: ['gemini-1.5-flash', 'gemini-1.5-pro'],
          features: ['caching', 'batching'],
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'text', 'required' => true },
                { 'name' => 'categories', 'required' => true }
              ]
            },
            'transform_input' => {
              'categories' => { 'from' => 'categories', 'to' => 'text' }
            },
            'payload' => {
              'format' => 'vertex_prompt',
              'template' => 'Classify this text into one of these categories:\n{categories}\n\nText: {text}\n\nRespond with JSON: {"category": "name", "confidence": 0.0-1.0}',
              'system' => 'You are a classification expert. Always return valid JSON.'
            },
            'endpoint' => {
              'path' => ':generateContent'
            },
            'extract' => {
              'format' => 'vertex_json'
            }
          },
          defaults: {
            'temperature' => 0.1
          }
        },
        
        # Embedding Operations
        'text.embed' => {
          description: 'Generate text embeddings',
          capability: 'embedding',
          supported_models: ['text-embedding-004', 'textembedding-gecko'],
          features: ['batching', 'caching'],
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'texts', 'required' => true }
              ],
              'constraints' => [
                { 'type' => 'max_items', 'field' => 'texts', 'value' => 100 }
              ]
            },
            'payload' => {
              'format' => 'embedding'
            },
            'endpoint' => {
              'path' => ':predict',
              'method' => 'POST'
            },
            'extract' => {
              'format' => 'embeddings'
            }
          }
        },
        
        # Multimodal Operations
        'multimodal.analyze' => {
          description: 'Analyze images with text prompts',
          capability: 'generation',
          supported_models: ['gemini-1.5-pro', 'gemini-1.5-flash'],
          features: ['streaming'],
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'prompt', 'required' => true },
                { 'name' => 'images', 'required' => true }
              ]
            },
            'payload' => {
              'format' => 'multimodal'
            },
            'endpoint' => {
              'path' => ':generateContent'
            },
            'extract' => {
              'format' => 'vertex_text'
            }
          }
        },
        
        # Vector Operations
        'vector.upsert_datapoints' => {
          description: 'Upsert datapoints into a Vector Search index',
          capability: 'vector',
          supported_models: [], # not model-driven
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'index',      'required' => true },
                { 'name' => 'datapoints', 'required' => true }
              ]
            },
            'payload'  => { 'format' => 'upsert_datapoints' },
            'endpoint' => {
              'family' => 'vector_indexes',
              'path'   => ':upsertDatapoints',
              'method' => 'POST'
            },
            'extract'  => { 'format' => 'raw' }, # empty body on success
            'post_process' => 'add_upsert_ack'
          }
        },

        'vector.find_neighbors' => {
          description: 'Find nearest neighbors from a deployed index',
          capability: 'vector',
          supported_models: [], # not model-driven
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'index_endpoint',    'required' => true },
                { 'name' => 'deployed_index_id', 'required' => true },
                { 'name' => 'queries',           'required' => true }
              ],
              'constraints' => [
                # Exactly one locator per query: vector OR datapoint_id
                {
                  'type'   => 'xor',
                  'scope'  => 'queries[]',
                  'fields' => ['feature_vector', 'datapoint_id'],
                  'aliases'=> { 'feature_vector' => ['vector'] } # honor your alias
                },
                # If a query omits neighbor_count, allow top-level neighbor_count or the internal default (10)
                {
                  'type'               => 'fallback_required',
                  'scope'              => 'queries[]',
                  'field'              => 'neighbor_count',
                  'fallback_to_root'   => 'neighbor_count',
                  'default_if_absent'  => 10  # matches your payload fallback
                }
              ]
            },
            'payload'  => { 'format' => 'find_neighbors' },
            'endpoint' => {
              'family' => 'vector_index_endpoints',
              'path'   => ':findNeighbors',
              'method' => 'POST'
            },
            'extract'  => { 'format' => 'raw' },
            'post_process' => 'normalize_find_neighbors'
          }
        }       
      }
    end,
    
    # Configuration Registry - User preferences
    configuration_registry: lambda do |connection, user_config|
      {
        # Model selection
        models: {
          default: user_config['model'] || connection['default_model'] || 'gemini-1.5-flash',
          strategy: connection['optimization_mode'] || 'balanced',
          mode: user_config['model_mode'] || 'auto'
        },
        
        # Generation settings
        generation: {
          temperature: user_config['temperature'],
          max_tokens: user_config['max_tokens'],
          top_p: user_config['top_p'],
          top_k: user_config['top_k']
        }.compact,
        
        # Features
        features: {
          caching: {
            enabled: connection['enable_caching'] != false,
            ttl: user_config['cache_ttl'] || 300
          },
          logging: {
            enabled: connection['enable_logging'] == true
          }
        },
        
        # Execution
        execution: {
          retry: {
            max_attempts: 3,
            backoff: 1.0
          },
          rate_limit: {
            rpm: 60
          }
        }
      }
    end,
    
    # Main execution method combining all layers
    execute_behavior: lambda do |connection, behavior, input, user_config = {}|
      behavior_def = call('behavior_registry')[behavior] or error("Unknown behavior: #{behavior}")
      local_input = call('deep_copy', input) # Work on a local copy only

      # Apply defaults without side effects
      if behavior_def[:defaults]
        behavior_def[:defaults].each { |k, v| local_input[k] = local_input.key?(k) ? local_input[k] : v }
      end

      # Bring model-selection keys into local_input so select_model can use them
      %w[model model_mode lock_model_revision].each do |k|
        if user_config.key?(k) && !user_config[k].nil?
          local_input[k] = user_config[k]
        end
      end      

      cfg = call('configuration_registry', connection, user_config)
      operation_config = JSON.parse(JSON.dump(behavior_def[:config_template] || {})) # build op config from template

      # Bring generation settings into the local input (don’t mutate cfg)
      if cfg[:generation]
        cfg[:generation].each { |k, v| local_input[k] = v unless v.nil? }
      end

      operation_config['model']     = call('select_model', behavior_def, cfg, local_input)
      operation_config['resilience'] = cfg[:execution]

      # Caching key is derived from local_input
      if cfg[:features][:caching][:enabled]
        cache_key = "vertex_#{behavior}_#{local_input.to_json.hash}"
        if (hit = call('memo_get', cache_key))
          return hit
        end
      end

      result = call('execute_pipeline', connection, behavior, local_input, operation_config)

      if cfg[:features][:caching][:enabled]
        call('memo_put', cache_key, result, cfg[:features][:caching][:ttl] || 300)
      end

      result
    end,
    
    # ============================================
    # HELPER METHODS
    # ============================================
    
    # Post-processing methods
    add_upsert_ack: lambda do |response, input|
      # response is empty on success; return a useful ack
      {
        'ack'         => 'upserted',
        'count'       => Array(input['datapoints']).size,
        'index'       => input['index'],
        'empty_body'  => (response.nil? || response == {})
      }
    end,

    add_word_count: lambda do |response, input|
      if response.is_a?(String)
        { 
          'result' => response,
          'word_count' => response.split.size
        }
      else
        {
          'result' => response,
          'word_count' => response.to_s.split.size
        }
      end
    end,
    
    # Template application
    apply_template: lambda do |template, variables|
      return template unless template && variables
      
      result = template.dup
      variables.each do |key, value|
        result = result.gsub("{#{key}}", value.to_s)
      end
      result
    end,

    # Approximation of token count
    approx_token_count: lambda do |text|
      # Fast, side-effect-free approximation
      ((text.to_s.length) / 4.0).ceil
    end,

    # Build endpoint URL
    build_endpoint_url: lambda do |connection, endpoint_config, input|
      v = connection['version']
      api_version = (v && !v.to_s.strip.empty?) ? v : 'v1'
      region = connection['region']
      base_regional = "https://#{region}-aiplatform.googleapis.com/#{api_version}"

      family = endpoint_config['family']

      case family
      when 'publisher_models'
        api_version = (connection['version'].to_s.strip.empty? ? 'v1' : connection['version'])
        publisher   = endpoint_config['publisher'] || 'google'
        "https://aiplatform.googleapis.com/#{api_version}/publishers/#{publisher}/models"
      when 'vector_indexes' # admin/data-plane ops on Index resources
        index = call('qualify_resource', connection, 'index', input['index'] || endpoint_config['index'])
        "#{base_regional}/#{index}#{endpoint_config['path']}" # e.g., ':upsertDatapoints'

      when 'vector_index_endpoints' # query via MatchService (vbd host)
        base  = call('vector_search_base', connection, input)
        ie    = call('qualify_resource', connection, 'index_endpoint',
                    input['index_endpoint'] || endpoint_config['index_endpoint'])
        "#{base}/#{ie}#{endpoint_config['path']}" # e.g., ':findNeighbors'

      else
        base_host = (region == 'global') ? 'aiplatform.googleapis.com' : "#{region}-aiplatform.googleapis.com"
        base_url  = "https://#{base_host}/#{api_version}"

        model   = input['model'] || connection['default_model'] || 'gemini-1.5-flash'
        model_id = model.to_s

        # Honor lock model revision input flag
        lock_rev = input['lock_model_revision'] == true || endpoint_config['require_version'] == true
        if lock_rev && !model_id.match?(/-\d{3,}$/)
          model_id = call('resolve_model_version', connection, model_id)
        end
        # Only resolve to a numeric version when explicitly requested by endpoint config
        if endpoint_config['require_version'] == true && !model_id.match?(/-\d{3,}$/)
          model_id = call('resolve_model_version', connection, model_id)
        end

        model_path = "projects/#{connection['project']}/locations/#{region}/publishers/google/models/#{model_id}"

        # If the user supplies a custom path, replace the the critical elements with those from the connection
        if endpoint_config['custom_path']
          endpoint_config['custom_path']
            .gsub('{project}',  connection['project'])
            .gsub('{region}',   region)
            .gsub('{endpoint}', connection['vector_search_endpoint'] || '')
        else
          "#{base_url}/#{model_path}#{endpoint_config['path'] || ':generateContent'}"
        end
      end
    end,
    
    build_generation_config: lambda do |vars|
      {
        'temperature'     => vars['temperature'] || 0.7,
        'maxOutputTokens' => vars['max_tokens']  || 2048,
        'topP'            => vars['top_p']       || 0.95,
        'topK'            => vars['top_k']       || 40,
        'stopSequences'   => vars['stop_sequences']
      }.compact
    end,

    # Build request headers
    build_headers: lambda do |connection|
      {
        'Content-Type' => 'application/json',
        'X-Goog-User-Project' => connection['project']
      }
    end,

    # Rate limiting
    check_rate_limit: lambda do |operation, limits|
      rpm  = (limits['rpm'] || limits[:rpm]).to_i
      window_id     = Time.now.to_i / 60
      window_start  = window_id * 60
      key           = "rate_#{operation}_#{window_id}"

      count = call('memo_get', key) || 0
      error("Rate limit exceeded for #{operation}. Please wait before retrying.") if count >= rpm

      new_count = count + 1
      reset_in  = (window_start + 60) - Time.now.to_i
      reset_in  = 60 if reset_in <= 0

      call('memo_put', key, new_count, reset_in)

      { 'rpm' => rpm, 'count' => new_count, 'reset_in_s' => reset_in, 'window_started_at' => Time.at(window_start).utc.iso8601 }
    end,

    chunk_by_tokens: lambda do |items:, token_ceiling:, max_items:, max_body_bytes: nil|
      token_cap = token_ceiling.to_i
      token_cap = 8000 if token_cap <= 0 # conservative fallback if not provided
      max_items = (max_items || 100).to_i
      max_items = 1 if max_items <= 0
      max_body  = max_body_bytes ? max_body_bytes.to_i : nil

      batches   = []
      oversized = []

      current       = []
      current_tokens= 0
      current_bytes = 0

      # crude but steady overheads so we don’t undercount request size
      per_item_overhead = 64
      base_overhead     = 512

      items.each do |item|
        txt = item['text'].to_s
        t   = call('approx_token_count', txt)
        b   = txt.bytesize + per_item_overhead

        # single-item guards
        if t > token_cap
          oversized << { 'item' => item, 'reason' => "estimated tokens #{t} exceed ceiling #{token_cap}" }
          next
        end
        if max_body && (b + base_overhead) > max_body
          oversized << { 'item' => item, 'reason' => "approx body bytes #{b + base_overhead} exceed limit #{max_body}" }
          next
        end

        # would adding this item break any limit?
        if !current.empty? &&
          (current_tokens + t > token_cap ||
            current.length + 1 > max_items ||
            (max_body && current_bytes + b + base_overhead > max_body))
          batches << current
          current        = []
          current_tokens = 0
          current_bytes  = 0
        end

        current << item
        current_tokens += t
        current_bytes  += b
      end

      batches << current unless current.empty?

      { 'batches' => batches, 'oversized' => oversized }
    end,

    coerce_kwargs: lambda do |*args, **kwargs|
      # Non-destructive copies
      positional = args.dup
      kw = kwargs.dup

      # If caller passed a trailing Hash, treat it as kwargs (merged with explicit kwargs)
      if positional.last.is_a?(Hash)
        trailing = positional.pop
        # deep copy to avoid side-effects
        trailing_copy = JSON.parse(JSON.dump(trailing)) rescue trailing.dup
        trailing_sym  = trailing_copy.each_with_object({}) do |(k, v), acc|
          key = (k.respond_to?(:to_sym) ? k.to_sym : k)
          acc[key] = v
        end
        # Explicit kwargs take precedence
        kw = trailing_sym.merge(kw) { |_key, left, right| right }
      end

      # Ensure symbolized keys for kwargs
      kw = kw.each_with_object({}) do |(k, v), acc|
        key = (k.respond_to?(:to_sym) ? k.to_sym : k)
        acc[key] = v
      end

      [positional, kw]
    end,
    
    # Safely duplicate object
    deep_copy: lambda { |obj| JSON.parse(JSON.dump(obj)) },

    # Iterate within a scope path like 'queries[]' or root ('$' or nil)
    each_in_scope: lambda do |data, scope|
      s = scope.to_s
      if s.end_with?('[]')
        key = s[0..-3] # strip []
        arr = Array(data[key]) # safe
        arr.each_with_index.map { |item, idx| [item || {}, "#{key}[#{idx}]"] }
      else
        [[data, '$']]
      end
    end,

    # RETRY HELPER
    error_hint: lambda do |connection, code, status|
      c = code.to_i
      case c
      when 401
        # keep small + actionable
        'Unauthorized. Re‑authenticate; then check project/region, API enablement, and roles.'
      when 403
        'Forbidden. Check project/region, API enablement, and roles.'
      when 404
        'Not found. Check project/region (feature/model availability) and the resource id.'
      when 429
        'Rate limit/quota. Reduce request rate or increase quota. Will honor Retry‑After when present.'
      else
        nil
      end
    end,

    # Extract user configuration safely
    extract_user_config: lambda do |input, cfg_enabled = false, config_ctx = {}|
      cfg = {}
      config_ctx ||= {}

      # Prefer config_fields values; fall back to input (back-compat)
      mode = (config_ctx['model_mode'] || input['model_mode'] || '').to_s
      explicit_model = input['model'] || input['model_override'] || config_ctx['model']

      case mode
      when 'explicit'
        cfg['model'] = explicit_model if call('value_present', explicit_model)
      when 'connection', 'auto', ''
        # no-op; use selection logic defaults
      else
        # unknown mode: treat as legacy explicit if model present
        cfg['model'] = explicit_model if call('value_present', explicit_model)
      end

      cfg['model_mode']          = mode unless mode.empty?
      # After (prefer config_fields, fall back to input for completeness)
      if config_ctx.key?('lock_model_revision')
        cfg['lock_model_revision'] = config_ctx['lock_model_revision']
      elsif input.key?('lock_model_revision')
        cfg['lock_model_revision'] = input['lock_model_revision']
      end

      # Advanced tuning (unchanged)
      if cfg_enabled
        cfg['temperature'] = input['temperature'] if input.key?('temperature')
        cfg['max_tokens']  = input['max_tokens']  if input.key?('max_tokens')
        cfg['cache_ttl']   = input['cache_ttl']   if input.key?('cache_ttl')
      end

      cfg.compact
    end,
  
    # Batch execution
    execute_batch_behavior: lambda do |connection, behavior, items, batch_size, strategy, options = {}|
      results = []
      errors = []
      total_processed = 0

      local_items = call('deep_copy', Array(items))
      
      # 1) Build batches according to strategy
      batches =
        if strategy.to_s == 'tokens'
          chunk = call('chunk_by_tokens',
            items: local_items,
            token_ceiling: (options['token_ceiling'] || options[:token_ceiling]),
            max_items: (options['max_items_per_batch'] || options[:max_items_per_batch] || 100),
            max_body_bytes: (options['max_body_bytes'] || options[:max_body_bytes])
          )
          # surface oversize items as per-batch errors (unchanged error shape: batch + error)
          Array(chunk['oversized']).each do |o|
            errors << { 'batch' => [o['item']], 'error' => "Skipped item: #{o['reason']}" }
          end
          chunk['batches'] || []
        else
          size  = (batch_size || 10).to_i
          limit = (options['max_items_per_batch'] || options[:max_items_per_batch] || size).to_i
          size  = [[size, limit].min, 1].max
          local_items.each_slice(size).to_a
        end

      # 2) Execute batches
      batches.each do |batch|
        begin
          if behavior.include?('embed')
            texts = batch.map { |item| item['text'] }

            payload = { 'texts' => texts }
            unique_tasks = batch.map { |i| i['task_type'] }.compact.uniq
            payload['task_type'] = unique_tasks.first if unique_tasks.length == 1

            batch_result = call('execute_behavior', connection, behavior, payload)

            # For embeddings, API is truly batchable: one result per batch (keep prior shape)
            results.concat([batch_result])
            total_processed += batch.length

          else
            # Non-embeddings: execute per-item so partial failures are surfaced
            batch.each do |item|
              begin
                item_result = call('execute_behavior', connection, behavior, item)
                results << item_result
                total_processed += 1
              rescue => e
                errors << { 'batch' => [item], 'error' => e.message }
              end
            end
          end

        rescue => e
          # catastrophic batch failure (network, quota, etc.)
          errors << { 'batch' => batch, 'error' => e.message }
        end
      end
      
      {
        'success'         => errors.empty?,
        'results'         => results,
        'errors'          => errors,
        'total_processed' => total_processed,
        'total_errors'    => errors.length
      }
    end,
  
    # RETRY HELPER
    format_user_error: lambda do |err|
      base = "Vertex AI error #{err['code']}"
      base += " #{err['status']}" if err['status']
      head = "#{base}: #{err['summary']}"
      tags = ["corr_id=#{err['correlation_id']}"]
      tags << "remote_id=#{err['remote_request_id']}" if err['remote_request_id']
      msg = "#{head} [#{tags.join(' ')}]"
      msg += " — Hint: #{err['hint']}" if err['hint']
      msg
    end,

    # Get behavior input fields dynamically
    get_behavior_input_fields: lambda do |behavior, show_advanced, ui_cfg = {}|
      show_advanced = !!show_advanced
      ui_cfg ||= {}
      # If config-driven mode exists, show the model picker only when explicit.
      # If not (old recipes), include it for backward-compatibility.
      explicit      = (ui_cfg['model_mode'] == 'explicit')
      legacy_mode   = !ui_cfg.key?('model_mode')
      include_model = false

      behavior_def = call('behavior_registry')[behavior]
      return [] unless behavior_def
      
      # Map behavior to input fields
      case behavior
      when 'text.generate'
        fields = [
          { name: 'prompt', label: 'Prompt', control_type: 'text-area', optional: false },
        ]
        if include_model
          fields << {
            name: 'model', label: 'Model', group: 'Model & tuning', control_type: 'select', optional: true, sticky: true,
            pick_list: 'models_dynamic_for_behavior', pick_list_params: { behavior: behavior }, toggle_hint: 'Select from list',
            toggle_field: { name: 'model', label: 'Model (custom id)', type: 'string', control_type: 'text', optional: true, toggle_hint: 'Provide custom value' }
          }
          fields << {
            name: 'lock_model_revision', label: 'Lock to latest numbered revision',
            control_type: 'checkbox', group: 'Model & tuning',
            hint: 'Resolves alias (e.g., gemini-1.5-pro) to current highest revision at runtime.'
          }
        end
        if show_advanced
          fields += [
            { name: 'system', label: 'System instruction', control_type: 'text-area', optional: true, group: 'Advanced', hint: 'Optional system prompt to guide the model' },
            { name: 'safety_settings', label: 'Safety settings', type: 'array', of: 'object', group: 'Advanced',
              properties: [
                { name: 'category',  control_type: 'select', pick_list: 'safety_categories',  optional: false },
                { name: 'threshold', control_type: 'select', pick_list: 'safety_thresholds',  optional: false },
                { name: 'method',    control_type: 'select', pick_list: 'safety_methods',     optional: true }
              ]}
          ]
        end
        fields
      when 'text.translate'
        fields = [
          { name: 'text', label: 'Text to Translate', control_type: 'text-area', optional: false },
          { name: 'target_language', label: 'Target Language', control_type: 'select', pick_list: 'languages', optional: false },
          { name: 'source_language', label: 'Source Language', control_type: 'select', pick_list: 'languages', optional: true, hint: 'Leave blank for auto-detection' }
        ]
        if include_model
          fields << {
            name: 'model', label: 'Model', group: 'Model & tuning', control_type: 'select', optional: true, sticky: true,
            pick_list: 'models_dynamic_for_behavior', pick_list_params: { behavior: behavior }, toggle_hint: 'Select from list',
            toggle_field: { name: 'model', label: 'Model (custom id)', type: 'string', control_type: 'text', optional: true, toggle_hint: 'Provide custom value' }
          }
          fields << {
            name: 'lock_model_revision', label: 'Lock to latest numbered revision',
            control_type: 'checkbox', group: 'Model & tuning',
            hint: 'Resolves alias (e.g., gemini-1.5-pro) to current highest revision at runtime.'
          }
        end
        if show_advanced
          fields += [
            { name: 'system', label: 'System instruction', control_type: 'text-area', optional: true, group: 'Advanced', hint: 'Optional system prompt to guide the model' },
            { name: 'safety_settings', label: 'Safety settings', type: 'array', of: 'object', group: 'Advanced',
              properties: [
                { name: 'category',  control_type: 'select', pick_list: 'safety_categories',  optional: false },
                { name: 'threshold', control_type: 'select', pick_list: 'safety_thresholds',  optional: false },
                { name: 'method',    control_type: 'select', pick_list: 'safety_methods',     optional: true }
              ]}
          ]
        end
        fields
      when 'text.summarize'
        fields = [
          { name: 'text', label: 'Text to Summarize', control_type: 'text-area', optional: false },
        ]
        if include_model
          fields << {
            name: 'model', label: 'Model', group: 'Model & tuning', control_type: 'select', optional: true, sticky: true,
            pick_list: 'models_dynamic_for_behavior', pick_list_params: { behavior: behavior }, toggle_hint: 'Select from list',
            toggle_field: { name: 'model', label: 'Model (custom id)', type: 'string', control_type: 'text', optional: true, toggle_hint: 'Provide custom value' }
          }
          fields << {
            name: 'lock_model_revision', label: 'Lock to latest numbered revision',
            control_type: 'checkbox', group: 'Model & tuning',
            hint: 'Resolves alias (e.g., gemini-1.5-pro) to current highest revision at runtime.'
          }
        end
        if show_advanced
          fields += [
            { name: 'system', label: 'System instruction', control_type: 'text-area', optional: true, group: 'Advanced', hint: 'Optional system prompt to guide the model' },
            { name: 'safety_settings', label: 'Safety settings', type: 'array', of: 'object', group: 'Advanced',
              properties: [
                { name: 'category',  control_type: 'select', pick_list: 'safety_categories',  optional: false },
                { name: 'threshold', control_type: 'select', pick_list: 'safety_thresholds',  optional: false },
                { name: 'method',    control_type: 'select', pick_list: 'safety_methods',     optional: true }
              ]}
          ]
        end
        fields
      when 'text.classify'
        fields = [
          { name: 'text', label: 'Text to Classify', control_type: 'text-area', optional: false },
          { name: 'categories', label: 'Categories', type: 'array', of: 'object', properties: [
            { name: 'name', label: 'Category Name' },
            { name: 'description', label: 'Description' }
          ]}
        ]
        if include_model
          fields << {
            name: 'model', label: 'Model', group: 'Model & tuning', control_type: 'select', optional: true, sticky: true,
            pick_list: 'models_dynamic_for_behavior', pick_list_params: { behavior: behavior }, toggle_hint: 'Select from list',
            toggle_field: { name: 'model', label: 'Model (custom id)', type: 'string', control_type: 'text', optional: true, toggle_hint: 'Provide custom value' }
          }
          fields << {
            name: 'lock_model_revision', label: 'Lock to latest numbered revision',
            control_type: 'checkbox', group: 'Model & tuning',
            hint: 'Resolves alias (e.g., gemini-1.5-pro) to current highest revision at runtime.'
          }
        end
        if show_advanced
          fields += [
            { name: 'system', label: 'System instruction', control_type: 'text-area', optional: true, group: 'Advanced', hint: 'Optional system prompt to guide the model' },
            { name: 'safety_settings', label: 'Safety settings', type: 'array', of: 'object', group: 'Advanced',
              properties: [
                { name: 'category',  control_type: 'select', pick_list: 'safety_categories',  optional: false },
                { name: 'threshold', control_type: 'select', pick_list: 'safety_thresholds',  optional: false },
                { name: 'method',    control_type: 'select', pick_list: 'safety_methods',     optional: true }
              ]}
          ]
        end
        fields
      when 'text.embed'
        fields = [
          { name: 'texts', label: 'Texts to Embed', type: 'array', of: 'string', optional: false },
        ]
        if include_model
          fields << {
            name: 'model', label: 'Model', group: 'Model & tuning', control_type: 'select', optional: true, sticky: true,
            pick_list: 'models_dynamic_for_behavior', pick_list_params: { behavior: behavior }, toggle_hint: 'Select from list',
            toggle_field: { name: 'model', label: 'Model (custom id)', type: 'string', control_type: 'text', optional: true, toggle_hint: 'Provide custom value' }
          }
          fields << {
            name: 'lock_model_revision', label: 'Lock to latest numbered revision',
            control_type: 'checkbox', group: 'Model & tuning',
            hint: 'Resolves alias (e.g., gemini-1.5-pro) to current highest revision at runtime.'
          }
        end
        if show_advanced
          fields += [
            { name: 'system', label: 'System instruction', control_type: 'text-area', optional: true, group: 'Advanced', hint: 'Optional system prompt to guide the model' },
            { name: 'safety_settings', label: 'Safety settings', type: 'array', of: 'object', group: 'Advanced',
              properties: [
                { name: 'category',  control_type: 'select', pick_list: 'safety_categories',  optional: false },
                { name: 'threshold', control_type: 'select', pick_list: 'safety_thresholds',  optional: false },
                { name: 'method',    control_type: 'select', pick_list: 'safety_methods',     optional: true }
              ]}
          ]
        end
        fields
      when 'vector.upsert_datapoints'
        [
          { name: 'index', label: 'Index', hint: 'Index resource or ID (e.g. projects/.../indexes/IDX or IDX)', optional: false },
          { name: 'datapoints', label: 'Datapoints', type: 'array', of: 'object', properties: [
            { name: 'datapoint_id', label: 'Datapoint ID', optional: false },
            { name: 'feature_vector', label: 'Feature vector', type: 'array', of: 'number', optional: false },
            { name: 'restricts', type: 'array', of: 'object', properties: [
              { name: 'namespace' }, { name: 'allowList', type: 'array', of: 'string' }, { name: 'denyList', type: 'array', of: 'string' }
            ]},
            { name: 'numeric_restricts', type: 'array', of: 'object', properties: [
              { name: 'namespace' }, { name: 'op' }, { name: 'valueInt' }, { name: 'valueFloat', type: 'number' }, { name: 'valueDouble', type: 'number' }
            ]},
            { name: 'crowding_tag', type: 'object', properties: [{ name: 'crowdingAttribute' }] },
            { name: 'embedding_metadata', type: 'object' }
          ]}
        ]
      when 'vector.find_neighbors'
        [
          { name: 'endpoint_host', label: 'Public endpoint host (vdb)', hint: 'Overrides connection host just for this call (e.g. 123...vdb.vertexai.goog)', optional: true },
          { name: 'index_endpoint', label: 'Index Endpoint', hint: 'Resource or ID (e.g. projects/.../indexEndpoints/IEP or IEP)', optional: false },
          { name: 'deployed_index_id', label: 'Deployed Index ID', optional: false },
          { name: 'neighbor_count', label: 'Neighbors per query', type: 'integer', default: 10 },
          { name: 'return_full_datapoint', label: 'Return full datapoint', control_type: 'checkbox' },
          { name: 'queries', label: 'Queries', type: 'array', of: 'object', properties: [
            { name: 'datapoint_id', label: 'Query datapoint ID' },
            { name: 'feature_vector', label: 'Query vector', type: 'array', of: 'number', hint: 'Use either vector or datapoint_id' },
            { name: 'neighbor_count', label: 'Override neighbors for this query', type: 'integer' },
            { name: 'restricts', type: 'array', of: 'object', properties: [
              { name: 'namespace' }, { name: 'allowList', type: 'array', of: 'string' }, { name: 'denyList', type: 'array', of: 'string' }
            ]},
            { name: 'numeric_restricts', type: 'array', of: 'object', properties: [
              { name: 'namespace' }, { name: 'op' }, { name: 'valueInt' }, { name: 'valueFloat', type: 'number' }, { name: 'valueDouble', type: 'number' }
            ]}
          ]}
        ]
      when 'multimodal.analyze'
        fields = [
          { name: 'prompt', label: 'Analysis Prompt', control_type: 'text-area', optional: false },
          { name: 'images', label: 'Images', type: 'array', of: 'object', properties: [
            { name: 'data', label: 'Image Data (Base64)', control_type: 'text-area' },
            { name: 'mime_type', label: 'MIME Type', default: 'image/jpeg' }
          ]}
        ]
        if include_model
          fields << {
            name: 'model', label: 'Model', group: 'Model & tuning', control_type: 'select', optional: true, sticky: true,
            pick_list: 'models_dynamic_for_behavior', pick_list_params: { behavior: behavior }, toggle_hint: 'Select from list',
            toggle_field: { name: 'model', label: 'Model (custom id)', type: 'string', control_type: 'text', optional: true, toggle_hint: 'Provide custom value' }
          }
          fields << {
            name: 'lock_model_revision', label: 'Lock to latest numbered revision',
            control_type: 'checkbox', group: 'Model & tuning',
            hint: 'Resolves alias (e.g., gemini-1.5-pro) to current highest revision at runtime.'
          }
        end
        if show_advanced
          fields += [
            { name: 'system', label: 'System instruction', control_type: 'text-area', optional: true, group: 'Advanced', hint: 'Optional system prompt to guide the model' },
            { name: 'safety_settings', label: 'Safety settings', type: 'array', of: 'object', group: 'Advanced',
              properties: [
                { name: 'category',  control_type: 'select', pick_list: 'safety_categories',  optional: false },
                { name: 'threshold', control_type: 'select', pick_list: 'safety_thresholds',  optional: false },
                { name: 'method',    control_type: 'select', pick_list: 'safety_methods',     optional: true }
              ]}
          ]
        end
        fields
      else
        []
      end
      
      # Add advanced fields if requested
      if show_advanced
        fields += [
          { name: 'model_override', label: 'Override Model', control_type: 'select', group: 'Advanced',
            pick_list: 'models_dynamic_for_behavior', pick_list_params: { behavior: behavior }, optional: true },
          { name: 'temperature', label: 'Temperature', type: 'number', group: 'Advanced', hint: '0.0 to 1.0' },
          { name: 'max_tokens', label: 'Max Tokens', type: 'integer', group: 'Advanced' },
          { name: 'cache_ttl', label: 'Cache TTL (seconds)', type: 'integer', group: 'Advanced', default: 300 }
        ]
      end
      
      fields
    end,
    
    # Get behavior output fields
    get_behavior_output_fields: lambda do |behavior|
      case behavior
      when 'text.generate'
        [{ name: 'result', label: 'Generated Text' }]
      when 'text.translate'
        [
          { name: 'result', label: 'Translated Text' },
          { name: 'detected_language', label: 'Detected Source Language' }
        ]
      when 'text.summarize'
        [
          { name: 'result', label: 'Summary' },
          { name: 'word_count', type: 'integer' }
        ]
      when 'text.classify'
        [
          { name: 'category', label: 'Selected Category' },
          { name: 'confidence', type: 'number' }
        ]
      when 'text.embed'
        [{ name: 'embeddings', type: 'array', of: 'array' }]
      when 'vector.upsert_datapoints'
        [
          { name: 'ack' }, { name: 'count', type: 'integer' }, { name: 'index' }, { name: 'empty_body', type: 'boolean' }
        ]
      when 'vector.find_neighbors'
        [
          { name: 'groups', type: 'array', of: 'object', properties: [
            { name: 'query_id' },
            { name: 'neighbors', type: 'array', of: 'object', properties: [
              { name: 'datapoint_id' }, { name: 'distance', type: 'number' }, { name: 'score', type: 'number' },
              { name: 'datapoint', type: 'object' }
            ]}
          ]}
        ]

      when 'multimodal.analyze'
        [{ name: 'result', label: 'Analysis' }]
      else
        [{ name: 'result' }]
      end
    end,

    # List Google publisher models (v1beta1)
    list_publisher_models: lambda do |connection, publisher: 'google'|
      cache_key = "pub_models:#{publisher}"
      if (cached = call('memo_get', cache_key))
        return cached
      end

      url = call('build_endpoint_url', connection, { 'family' => 'publisher_models', 'publisher' => publisher }, {})
      resp = call('http_request',
                  connection,
                  method: 'GET',
                  url: url,
                  headers: call('build_headers', connection),
                  retry_config: { max_attempts: 3, backoff: 1.0, retry_on: [429, 500, 502, 503, 504] })

      models = (resp['publisherModels'] || []) # shape per REST docs
      call('memo_put', cache_key, models, 3600)
      models
    end,

    memo_store: lambda { @__memo ||= {} },

    memo_get: lambda do |key|
      item = call('memo_store')[key]
      return nil unless item
      exp = item['exp']
      return nil if exp && Time.now.to_i > exp
      item['val']
    end,

    memo_put: lambda do |key, val, ttl=nil|
      call('memo_store')[key] = { 'val' => val, 'exp' => (ttl ? Time.now.to_i + ttl.to_i : nil) }
      val
    end,

    # Normalize FindNeighbors response into a stable, recipe-friendly shape
    normalize_find_neighbors: lambda do |resp, _input|
      # Expected: { "nearestNeighbors": [ { "id": "...?", "neighbors": [ { "datapoint": {...}, "distance": n } ] } ] }
      groups = (resp['nearestNeighbors'] || []).map do |nn|
        {
          'query_id' => nn['id'],
          'neighbors' => (nn['neighbors'] || []).map do |n|
            did  = n.dig('datapoint', 'datapointId')
            dist = n['distance']
            {
              'datapoint_id' => did,
              'distance'     => dist,
              'score'        => call('transform_data', input: dist, from_format: 'distance', to_format: 'similarity'),
              'datapoint'    => n['datapoint']
            }.compact
          end
        }
      end
      { 'groups' => groups }
    end,

    normalize_http_error: lambda do |connection, code:, body:, headers:, message:, url:, corr_id:, attempt:, duration_ms:|
      parsed = {}
      if body.is_a?(Hash)
        parsed = body
      else
        begin
          parsed = JSON.parse(body.to_s)
        rescue
          parsed = {}
        end
      end

      gerr    = parsed['error'].is_a?(Hash) ? parsed['error'] : {}
      status  = gerr['status']
      summary = (gerr['message'] || message || body.to_s).to_s.strip[0, 300] # compact
      hint    = call('error_hint', connection, code, status)

      remote_id = nil
      if headers
        remote_id = headers['x-request-id'] ||
                    headers['x-cloud-trace-context'] ||
                    headers['x-guploader-uploadid']
      end

      {
        'code'              => code.to_i,
        'status'            => status,
        'summary'           => summary,
        'hint'              => hint,
        'retryable'         => call('retryable_http_code', code),
        'retry_after_s'     => call('parse_retry_after', headers),
        'correlation_id'    => corr_id,
        'remote_request_id' => remote_id,
        'attempt'           => attempt,
        'duration_ms'       => duration_ms,
        'url'               => url
      }
    end,

    # Normalize safety settings
    normalize_safety_settings: lambda do |input|
      # Accepts either the new array shape or the legacy hash; returns array
      if input.is_a?(Array)
        # non-destructive copy with only supported keys
        return input.map do |r|
          {
            'category'  => r['category']  || r[:category],
            'threshold' => r['threshold'] || r[:threshold],
            'method'    => r['method']    || r[:method]
          }.compact
        end
      end

      # Legacy object: { harassment: 'BLOCK_...', hate_speech: 'BLOCK_...', ... }
      if input.is_a?(Hash)
        map = {
          'harassment'          => 'HARM_CATEGORY_HARASSMENT',
          'hate_speech'         => 'HARM_CATEGORY_HATE_SPEECH',
          'sexually_explicit'   => 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
          'dangerous_content'   => 'HARM_CATEGORY_DANGEROUS_CONTENT'
        }
        return input.each_with_object([]) do |(k, v), arr|
          next if v.nil? || v.to_s.strip.empty?
          cat = map[k.to_s]
          arr << { 'category' => cat, 'threshold' => v } if cat
        end
      end

      []
    end,

    # RETRY HELPER
    parse_retry_after: lambda do |headers|
      return nil unless headers
      ra = headers['Retry-After'] || headers['retry-after']
      return nil if ra.nil? || ra.to_s.strip.empty?
      # integer seconds only (safe & simple)
      ra.to_s =~ /^\d+$/ ? ra.to_i : nil
    end,

    # Resolve full resource names from short IDs, without mutating caller input
    qualify_resource: lambda do |connection, type, value|
      return value if value.to_s.start_with?('projects/')
      project = connection['project']
      region  = connection['region']
      case type.to_s
      when 'index'          then "projects/#{project}/locations/#{region}/indexes/#{value}"
      when 'index_endpoint' then "projects/#{project}/locations/#{region}/indexEndpoints/#{value}"
      else value
      end
    end,

    # Resolve an alias to the latest version available
    resolve_model_version: lambda do |connection, short|
      # If already versioned, keep it
      return short if short.to_s.match?(/-\d{3,}$/)

      cache_key = "model_resolve:#{short}"
      if (cached = call('memo_get', cache_key))
        return cached
      end

      ids = Array(call('list_publisher_models', connection))
              .map { |m| (m['name'] || '').split('/').last }
              .select { |id| id.start_with?("#{short}-") }

      latest = ids.max_by { |id| id[/-(\d+)$/, 1].to_i }

      # IMPORTANT: if nothing is found, fall back to the alias itself (Vertex supports aliases)
      chosen = latest || short
      call('memo_put', cache_key, chosen, 3600)
      chosen
    end,

    # RETRY HELPER
    retryable_http_code: lambda { |code|
      [408, 429, 500, 502, 503, 504].include?(code.to_i)
    },

    # Model selection logic
    select_model: lambda do |behavior_def, cfg, input|
      # 0) Back-compat: if step explicitly set model (old or new), take it.
      if (input['model'] && !input['model'].to_s.strip.empty?) ||
        (input['model_override'] && !input['model_override'].to_s.strip.empty?)
        return input['model'] || input['model_override']
      end

      mode      = (input['model_mode'] || cfg.dig(:models, :mode) || 'auto').to_s
      strategy  = (cfg.dig(:models, :strategy) || 'balanced').to_s
      supported = Array(behavior_def[:supported_models]).compact
      default   = cfg.dig(:models, :default)

      # Helper to prefer an item if supported; else first supported; else fallback to default
      prefer = lambda do |*candidates|
        cand = candidates.flatten.compact.find { |m| supported.include?(m) }
        cand || (supported.first || default)
      end

      case mode
      when 'connection'
        # Use the connection default even if it's an alias; API will accept aliases
        default || supported.first
      when 'explicit'
        # No explicit in input => fall back to connection default
        default || supported.first
      else # 'auto'
        if behavior_def[:capability].to_s == 'embedding'
          case strategy
          when 'cost'        then prefer.call('textembedding-gecko', 'text-embedding-004')
          when 'performance' then prefer.call('text-embedding-004', 'textembedding-gecko')
          else                    prefer.call('text-embedding-004', 'textembedding-gecko')
          end
        else # generation/multimodal
          case strategy
          when 'cost'        then prefer.call('gemini-1.5-flash', 'gemini-1.5-pro')
          when 'performance' then prefer.call('gemini-1.5-pro',   'gemini-1.5-flash')
          else                    prefer.call('gemini-1.5-flash', 'gemini-1.5-pro')
          end
        end
      end
    end,

    # === Telemetry schema helpers (shared) ===
    telemetry_envelope_fields: lambda do
      [
        { name: 'success', type: 'boolean' },
        { name: 'timestamp', type: 'datetime' },
        { name: 'metadata', type: 'object', properties: [
          { name: 'operation' }, { name: 'model' }
        ]},
        { name: 'trace', type: 'object', properties: call('trace_fields') }
      ]
    end,
    trace_fields: lambda do
      [
        { name: 'correlation_id' },
        { name: 'duration_ms', type: 'integer' },
        { name: 'attempt', type: 'integer' },
        { name: 'http_status', type: 'integer' },
        { name: 'remote_request_id' }, 
        { name: 'rate_limit', type: 'object', properties: [
          { name: 'rpm', type: 'integer' },
          { name: 'count', type: 'integer' },
          { name: 'reset_in_s', type: 'integer' },
          { name: 'window_started_at', type: 'datetime' }
        ]}
      ]
    end,
    # === END/Telemetry schema helpers===

    to_query: lambda do |params|
      encode = lambda do |s|
        # RFC3986 unreserved: ALPHA / DIGIT / "-" / "." / "_" / "~"
        s.to_s.bytes.map { |b|
          if (48..57).cover?(b) || (65..90).cover?(b) || (97..122).cover?(b) || [45,46,95,126].include?(b)
            b.chr
          else
            "%%%02X" % b
          end
        }.join
      end

      params.flat_map do |k, v|
        key = encode.call(k)
        if v.is_a?(Array)
          v.map { |e| "#{key}=#{encode.call(e)}" }
        else
          "#{key}=#{encode.call(v)}"
        end
      end.join('&')
    end,

    # Presence helper (nil, '', '  ', [], {} treated as absent)
    value_present: lambda do |v|
      return false if v.nil?
      return false if v.is_a?(String) && v.strip.empty?
      return false if v.respond_to?(:empty?) && v.empty?
      true
    end,

    # Build base for vector *query* calls. Prefer the public vdb host when provided.
    vector_search_base: lambda do |connection, input|
      host = (input['endpoint_host'] || connection['vector_search_endpoint']).to_s.strip
      v = connection['version']
      version = (v && !v.to_s.strip.empty?) ? v : 'v1'

      if host.empty?
        # Fallback to regional API host (works for admin ops; query should use public vdb host)
        "https://#{connection['region']}-aiplatform.googleapis.com/#{version}"
      elsif host.include?('vdb.vertexai.goog')
        "https://#{host}/#{version}"
      else
        # Allow passing a full https://... custom host
        host = host.sub(%r{\Ahttps?://}i, '')
        "https://#{host}/#{version}"
      end
    end

  },

  # ============================================
  # PICK LISTS
  # ============================================
  pick_lists: {

    all_models: lambda do |connection|
      [
        ['Gemini 1.5 Flash', 'gemini-1.5-flash'],
        ['Gemini 1.5 Pro', 'gemini-1.5-pro'],
        ['Gemini Embedding 001',  'gemini-embedding-001'],
        ['Text Embedding 005',    'text-embedding-005'],
        ['Text Embedding 004',    'text-embedding-004'],
        ['Text Embedding Gecko', 'textembedding-gecko']
      ]
    end,
    
    available_behaviors: lambda do |connection|
      behaviors = call('behavior_registry')
      behaviors.map do |key, config|
        [config[:description], key]
      end.sort_by { |label, _| label }
    end,
    
    batchable_behaviors: lambda do |connection|
      behaviors = call('behavior_registry')
      behaviors.select { |_, config| 
        config[:features]&.include?('batching') 
      }.map { |key, config|
        [config[:description], key]
      }
    end,
    
    embedding_tasks: lambda do |connection|
      [
        ['Document Retrieval', 'RETRIEVAL_DOCUMENT'],
        ['Query Retrieval', 'RETRIEVAL_QUERY'],
        ['Semantic Similarity', 'SEMANTIC_SIMILARITY'],
        ['Classification', 'CLASSIFICATION'],
        ['Clustering', 'CLUSTERING']
      ]
    end,

    gcp_regions: lambda do |connection|
      [
        ['US Central 1', 'us-central1'],
        ['US East 1', 'us-east1'],
        ['US East 4', 'us-east4'],
        ['US West 1', 'us-west1'],
        ['US West 4', 'us-west4']
      ]
    end,

    languages: lambda do |connection|
      [
        ['Auto-detect', 'auto'],
        ['English', 'en'],
        ['Spanish', 'es'],
        ['French', 'fr'],
        ['German', 'de'],
        ['Italian', 'it'],
        ['Portuguese', 'pt'],
        ['Japanese', 'ja'],
        ['Korean', 'ko'],
        ['Chinese (Simplified)', 'zh-CN'],
        ['Chinese (Traditional)', 'zh-TW']
      ]
    end,

    models_embedding_dynamic: lambda do |connection|
      call('list_publisher_models', connection)
        .map { |m| id = (m['name'] || '').split('/').last; [m['displayName'] || id, id] }
        .select { |_label, id| id.start_with?('text-embedding-') || id.start_with?('textembedding-') }
        .sort_by { |_label, id| - (id[/-(\d+)$/, 1].to_i) }
    end,

    models_for_behavior: lambda do |connection, input = {}|
      behavior = input['behavior']
      defn = call('behavior_registry')[behavior]

      if defn && defn[:supported_models]
        defn[:supported_models].map do |model|
          [model.split('-').map!(&:capitalize).join(' '), model]
        end
      else
        []
      end
    end,

    models_dynamic_for_behavior: lambda do |connection, behavior: nil, **_|
      prefixes = (behavior.to_s == 'text.embed') ? ['text-embedding-', 'textembedding-'] : ['gemini-']
      call('list_publisher_models', connection)
        .map { |m| id = (m['name'] || '').split('/').last; [m['displayName'] || id, id] }
        .select { |_label, id| prefixes.any? { |p| id.start_with?(p) } }
        .sort_by { |_label, id| - (id[/-(\d+)$/, 1].to_i) }
    end,

    models_generation_dynamic: lambda do |connection|
      call('list_publisher_models', connection)
        .map { |m| id = (m['name'] || '').split('/').last; [m['displayName'] || id, id] }
        .select { |_label, id| id.start_with?('gemini-') }
        .sort_by { |_label, id| - (id[/-(\d+)$/, 1].to_i) }
    end,

    safety_categories: lambda do |_connection|
      [
        ['Harassment',           'HARM_CATEGORY_HARASSMENT'],
        ['Hate speech',          'HARM_CATEGORY_HATE_SPEECH'],
        ['Sexually explicit',    'HARM_CATEGORY_SEXUALLY_EXPLICIT'],
        ['Dangerous content',    'HARM_CATEGORY_DANGEROUS_CONTENT']
      ]
    end,

    safety_levels: lambda do |_connection|
      [
        ['Block none',   'BLOCK_NONE'],
        ['Block low',    'BLOCK_LOW'],
        ['Block medium', 'BLOCK_MEDIUM'],
        ['Block high',   'BLOCK_HIGH']
      ]
    end,

    safety_thresholds: lambda do |_connection|
      [
        ['Block none',              'BLOCK_NONE'],
        ['Block only high',         'BLOCK_ONLY_HIGH'],
        ['Block medium and above',  'BLOCK_MEDIUM_AND_ABOVE'],
        ['Block low and above',     'BLOCK_LOW_AND_ABOVE']
      ]
    end,

    safety_methods: lambda do |_connection|
      [
        ['By severity',    'SEVERITY'],
        ['By probability', 'PROBABILITY']
      ]
    end
  },

  # ============================================
  # OBJECT DEFINITIONS (Reusable Schemas)
  # ============================================
  object_definitions: {
    generation_config: {
      fields: lambda do |connection|
        [
          { name: 'temperature', type: 'number', hint: 'Controls randomness (0-1)' },
          { name: 'max_tokens', type: 'integer', hint: 'Maximum response length' },
          { name: 'top_p', type: 'number', hint: 'Nucleus sampling' },
          { name: 'top_k', type: 'integer', hint: 'Top-k sampling' },
          { name: 'stop_sequences', type: 'array', of: 'string', hint: 'Stop generation at these sequences' }
        ]
      end
    },
    
    safety_settings: {
      fields: lambda do |_connection|
        [
          { name: 'category',  control_type: 'select', pick_list: 'safety_categories',  optional: false },
          { name: 'threshold', control_type: 'select', pick_list: 'safety_thresholds',  optional: false },
          { name: 'method',    control_type: 'select', pick_list: 'safety_methods',     optional: true,
            hint: 'Optional; defaults to model behavior' }
        ]
      end
    }
  },

  # ============================================
  # TRIGGERS (if needed)
  # ============================================
  triggers: {},
  
  # ============================================
  # CUSTOM ACTION SUPPORT
  # ============================================
  custom_action: true,
  custom_action_help: {
    body: 'Create custom Vertex AI operations using the established connection'
  }
}
