### **Project Definition**

**Title**: Nginx Rate Limiting a Distributed system [Distributed ratelimiter]
**Objective**: Create a Dockerized Nginx web server with custom rate-limiting logic using njs (Nginx JavaScript) to control API/endpoint access based on configurable rules.

1. Core Rate Limiting Features:

- Implement token bucket algorithm for rate limiting
- Support multiple rate limiting windows (e.g., per second, per minute)
- Store IP tracking data with expiration
- Return appropriate HTTP status codes (429 Too Many Requests)

2. IP and User Agent Management:

- IP blocking/whitelisting
- User Agent filtering (blacklist/whitelist)
- Extract and process HTTP headers for identification
- Maintain a list of allowed/blocked user agents

3. Security Features:

- Basic health checking for upstream services
- SSL/TLS validation for incoming requests
- Implement CA certificate validation
- Add OCSP stapling support

4. Lua Integration:

- Create Lua bindings for extended functionality
- Allow Lua scripts to modify rate limiting behavior
- Implement Lua-based custom rules

5. Performance and Lightweight Design:

- Use in-memory storage with expiration
- Optimize for low overhead and high throughput
- Minimal external dependencies

6. Configuration and Management:

- Support configuration through nginx.conf
- Allow dynamic updates to rate limits
- Provide basic statistics and monitoring

- Include test cases for various scenarios
- Validate correct behavior under load
- Ensure proper handling of edge cases

8. Documentation:

- Provide detailed installation instructions
- Include example configurations
- Document Lua extension capabilities

### **Boundary Conditions**

- **Performance**: Designed for single-instance deployments
- **Scale**: Optimized for <1000 RPS per instance
- **Persistence**: Rate counters reset on container restart
- **Compatibility**: Nginx 1.21+ with njs module


```
            [ Client ]
                |
         [ Load Balancer ]
          /       |       \
   [ Nginx+njs ] [ Nginx+njs ] [ Nginx+njs ]
          \        |        /
             [ Central Redis ]
```
