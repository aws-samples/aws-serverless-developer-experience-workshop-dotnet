// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using Amazon;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Amazon.DynamoDBv2.DocumentModel;
using Amazon.EventBridge;
using Amazon.EventBridge.Model;
using Amazon.Lambda.APIGatewayEvents;
using Amazon.Lambda.Core;
using Amazon.Util;
using Amazon.XRay.Recorder.Handlers.AwsSdk;
using AWS.Lambda.Powertools.Logging;
using AWS.Lambda.Powertools.Metrics;
using AWS.Lambda.Powertools.Tracing;
using Unicorn.Web.Common;
using DynamoDBContextConfig = Amazon.DynamoDBv2.DataModel.DynamoDBContextConfig;

// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Unicorn.Web.ApprovalService;

public class RequestApprovalFunction
{
    private readonly IDynamoDBContext _dynamoDbContext;
    private readonly IAmazonEventBridge _eventBindingClient;
    private string? _dynamodbTable;
    private string? _eventBusName;
    private string? _serviceNamespace;
    private const string Pattern = @"[a-z-]+\/[a-z-]+\/[a-z][a-z0-9-]*\/[0-9-]+";

    /// <summary>
    /// Default constructor. Initialises global variables for function.
    /// </summary>
    /// <exception cref="Exception">Init exception</exception>
    public RequestApprovalFunction()
    {
        // Instrument all AWS SDK calls
        AWSSDKHandler.RegisterXRayForAllServices();
        
        // Validate and set environment variables
        SetEnvironmentVariables();

        // Initialise DDB client
        AWSConfigsDynamoDB.Context.TypeMappings[typeof(PropertyRecord)] =
            new TypeMapping(typeof(PropertyRecord), _dynamodbTable);
        var config = new DynamoDBContextConfig { Conversion = DynamoDBEntryConversion.V2 };
        _dynamoDbContext = new DynamoDBContext(new AmazonDynamoDBClient(), config);
        
        // Initialise EventBridge client
        _eventBindingClient = new AmazonEventBridgeClient();
    }

    /// <summary>
    /// Testing constructor for PropertySearchFunction
    /// </summary>
    /// <param name="dynamoDbContext"></param>
    /// <param name="eventBindingClient"></param>
    public RequestApprovalFunction(IDynamoDBContext dynamoDbContext, IAmazonEventBridge eventBindingClient)
    {
        // Validate and set environment variables
        SetEnvironmentVariables();

        _dynamoDbContext = dynamoDbContext;
        _eventBindingClient = eventBindingClient;
    }

    /// <summary>
    /// Validate and set environment variables
    /// </summary>
    /// <exception cref="Exception">Generic exception thrown if any of the required environment variables cannot be set.</exception>
    private void SetEnvironmentVariables()
    {
        _dynamodbTable = Environment.GetEnvironmentVariable("DYNAMODB_TABLE") ?? "";
        if (string.IsNullOrEmpty(_dynamodbTable))
            throw new Exception("Environment variable DYNAMODB_TABLE is not defined.");

        _eventBusName = Environment.GetEnvironmentVariable("EVENT_BUS") ?? "";
        if (string.IsNullOrEmpty(_eventBusName))
            throw new Exception("Environment variable EVENT_BUS is not defined.");

        _serviceNamespace = Environment.GetEnvironmentVariable("SERVICE_NAMESPACE") ?? "";
        if (string.IsNullOrEmpty(_eventBusName))
            throw new Exception("Environment variable SERVICE_NAMESPACE is not defined.");
    }

    /// <summary>
    /// Helper method to generate APIGatewayProxyResponse
    /// </summary>
    /// <param name="message">The message to include in the payload.</param>
    /// <param name="statusCode">the HTTP status code</param>
    /// <returns>APIGatewayProxyResponse</returns>
    private static Task<APIGatewayProxyResponse> ApiResponse(string message, HttpStatusCode statusCode)
    {
        var body = new Dictionary<string, string>
        {
            { "message", message }
        };

        return Task.FromResult(new APIGatewayProxyResponse
        {
            Body = JsonSerializer.Serialize(body),
            StatusCode = (int)statusCode,
            Headers = new Dictionary<string, string>
            {
                { "Content-Type", "application/json" },
                { "X-Custom-Header", "application/json" }
            }
        });
    }

    /// <summary>
    /// Lambda handler for approving properties.
    /// </summary>
    /// <param name="apigProxyEvent">API Gateway Lambda Proxy Request that triggers the function.</param>
    /// <param name="context">The context for the Lambda function.</param>
    /// <returns>API Gateway Lambda Proxy Response.</returns>
    [Logging(LogEvent = true, CorrelationIdPath = CorrelationIdPaths.ApiGatewayRest)]
    [Metrics(CaptureColdStart = true)]
    [Tracing(CaptureMode = TracingCaptureMode.ResponseAndError)]
    public async Task<APIGatewayProxyResponse> FunctionHandler(APIGatewayProxyRequest apigProxyEvent,
        ILambdaContext context)
    {
        string propertyId;
        
        try
        {
            var request = JsonSerializer.Deserialize<RequestApprovalRequest>(apigProxyEvent.Body);
            propertyId = request?.PropertyId ?? "";
            Logger.LogInformation($"Requesting approval for property: {propertyId}");
        }
        catch (Exception e)
        {
            Logger.LogError(e);
            return await ApiResponse("Unable to parse event input as JSON", HttpStatusCode.BadRequest);
        }

        // Validate property ID
        if (string.IsNullOrWhiteSpace(propertyId) || !Regex.Match(propertyId, Pattern).Success)
        {
            return await ApiResponse($"Input invalid; must conform to regular expression: {Pattern}",
                HttpStatusCode.BadRequest);
        }

        var splitString = propertyId.Split('/');
        var country = splitString[0];
        var city = splitString[1];
        var street = splitString[2];
        var number = splitString[3];

        var pk = PropertyRecordHelper.GetPartitionKey(country, city);
        var sk = PropertyRecordHelper.GetSortKey(street, number);

        try
        {
            var properties = await QueryTableAsync(pk, sk).ConfigureAwait(false);
            
            if (!properties.Any())
            {
                return await ApiResponse("No property found in database with the requested property id",
                    HttpStatusCode.InternalServerError);
            }

            var property = properties.First();
            
            // Do not approve properties in an approved state
            if (string.Equals(property.Status, PropertyStatus.Approved, StringComparison.CurrentCultureIgnoreCase))
            {
                return await ApiResponse($"Property is already {property.Status}; no action taken", HttpStatusCode.InternalServerError);
            }
            // Reset status to pending, awaiting the result of the check.
            property.Status = PropertyStatus.Pending;

            // Publish the event
            await SendEventAsync(propertyId, property).ConfigureAwait(false);
            
            // Add custom metric for the number of approval requests
            Metrics.AddMetric("ApprovalsRequested", 1, MetricUnit.Count);
            
            Logger.LogInformation($"Storing new property in DynamoDB with PK {pk} and SK {sk}");
            
            await _dynamoDbContext.SaveAsync(property).ConfigureAwait(false);
            Logger.LogInformation($"Stored item in DynamoDB;");
        }
        catch (Exception e)
        {
            Logger.LogError(e);
            return await ApiResponse(e.Message, HttpStatusCode.InternalServerError);
        }
        
        return await ApiResponse("Approval Requested", HttpStatusCode.OK);
    }

    private async Task<List<PropertyRecord>> QueryTableAsync(string partitionKey, string sortKey)
    {
        var filter = new QueryFilter(PropertyNames.PrimaryKey, QueryOperator.Equal, partitionKey);
        filter.AddCondition(PropertyNames.SortKey, QueryOperator.BeginsWith, sortKey);

        return await _dynamoDbContext
            .FromQueryAsync<PropertyRecord>(new QueryOperationConfig { Filter = filter })
            .GetRemainingAsync()
            .ConfigureAwait(false);
    }

    private async Task SendEventAsync(string propertyId, PropertyRecord property)
    {
        var requestApprovalEvent = new RequestApprovalEvent
        {
            PropertyId = propertyId,
            Status = property.Status,
            Images = property.Images,
            Description = property.Description,
            Address = new RequestApprovalEventAddress
            {
                Country = property.Country,
                City = property.City,
                Number = property.PropertyNumber
            }
        };

        var message = new PutEventsRequestEntry
        {
            EventBusName = _eventBusName,
            Resources = new List<string> { propertyId },
            Detail = JsonSerializer.Serialize(requestApprovalEvent),
            DetailType = "PublicationApprovalRequested",
            Source = _serviceNamespace
        };

        var putRequest = new PutEventsRequest
        {
            Entries = new List<PutEventsRequestEntry> { message }
        };

        var response = await _eventBindingClient.PutEventsAsync(putRequest).ConfigureAwait(false);
        Logger.LogInformation(response);
        if (response.FailedEntryCount > 0)
        {
            throw new Exception($"Error sending requests to Event Bus; {response.FailedEntryCount} message(s) failed");
        }

        Logger.LogInformation(
            $"Sent event to EventBridge; {response.FailedEntryCount} records failed; {response.Entries.Count} entries received");
        
    }
}