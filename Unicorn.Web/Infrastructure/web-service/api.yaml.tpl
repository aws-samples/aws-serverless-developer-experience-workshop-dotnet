openapi: "3.0.1"
info:
  title: "Unicorn Web API"
  version: "1.0.0"
  description: Unicorn Properties Web Service API
paths:
  /request_approval:
    post:
      requestBody:
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/PublicationEvaluationRequestModel"
        required: true
      responses:
        "200":
          description: "200 response"
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Empty"
      x-amazon-apigateway-request-validator: "Validate body"
      x-amazon-apigateway-integration:
        credentials: "${UnicornWebApiIntegrationRoleArn}"
        httpMethod: "POST"
        uri: "arn:aws:apigateway:${AWS_Region}:sqs:path/${AWS_AccountId}/${UnicornWebIngestQueueName}"
        responses:
          default:
            statusCode: "200"
            responseTemplates:
              application/json: '{"message":"OK"}'
        requestParameters:
          integration.request.header.Content-Type: "'application/x-www-form-urlencoded'"
        requestTemplates:
          application/json: "Action=SendMessage&MessageBody=$input.body"
        passthroughBehavior: "never"
        type: "aws"
  /search/{country}/{city}:
    get:
      parameters:
        - name: country
          in: path
          required: true
          schema:
            type: string
        - name: city
          in: path
          required: true
          schema:
            type: string
      responses:
        "200":
          $ref: '#/components/responses/ListPropertiesResponseBody'
      x-amazon-apigateway-integration:
        credentials: "${UnicornWebApiIntegrationRoleArn}"
        httpMethod: "POST"
        uri: "arn:aws:apigateway:${AWS_Region}:lambda:path/2015-03-31/functions/${SearchFunctionArn}/invocations"
        responses:
          default:
            statusCode: "200"
        passthroughBehavior: "when_no_match"
        contentHandling: "CONVERT_TO_TEXT"
        type: "aws_proxy"
  /search/{country}/{city}/{street}:
    get:
      parameters:
        - name: country
          in: path
          required: true
          schema:
            type: string
        - name: city
          in: path
          required: true
          schema:
            type: string
        - name: street
          in: path
          required: true
          schema:
            type: string
      responses:
        "200":
          $ref: '#/components/responses/ListPropertiesResponseBody'
      x-amazon-apigateway-integration:
        credentials: "${UnicornWebApiIntegrationRoleArn}"
        httpMethod: "POST"
        uri: "arn:aws:apigateway:${AWS_Region}:lambda:path/2015-03-31/functions/${SearchFunctionArn}/invocations"
        responses:
          default:
            statusCode: "200"
        passthroughBehavior: "when_no_match"
        contentHandling: "CONVERT_TO_TEXT"
        type: "aws_proxy"
  /properties/{country}/{city}/{street}/{number}:
    get:
      parameters:
        - name: country
          in: path
          required: true
          schema:
            type: string
        - name: city
          in: path
          required: true
          schema:
            type: string
        - name: street
          in: path
          required: true
          schema:
            type: string
        - name: number
          in: path
          required: true
          schema:
            type: string
      responses:
        "200":
          $ref: '#/components/responses/PropertyDetailsResponseBody'
      x-amazon-apigateway-integration:
        credentials: "${UnicornWebApiIntegrationRoleArn}"
        httpMethod: "POST"
        uri: "arn:aws:apigateway:${AWS_Region}:lambda:path/2015-03-31/functions/${SearchFunctionArn}/invocations"
        responses:
          default:
            statusCode: "200"
        passthroughBehavior: "when_no_match"
        contentHandling: "CONVERT_TO_TEXT"
        type: "aws_proxy"
components:
  schemas:
    PublicationEvaluationRequestModel:
      required:
        - "property_id"
      type: "object"
      properties:
        property_id:
          type: string
    Empty:
      title: "Empty Schema"
      type: "object"
  responses:
    ListPropertiesResponseBody:
      description: 'OK'
      content:
        application/json:
          schema:
            type: array
            uniqueItems: true
            items:
              type: object
    PropertyDetailsResponseBody:
      description: 'OK'
      content:
        application/json:
          schema:
            type: array
            uniqueItems: true
            items:
              type: object
x-amazon-apigateway-request-validators:
  Validate body:
    validateRequestParameters: false
    validateRequestBody: true
