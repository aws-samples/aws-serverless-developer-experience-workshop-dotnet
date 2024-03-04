// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json;
using System.Text.RegularExpressions;
using Amazon;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Amazon.DynamoDBv2.DocumentModel;
using Amazon.EventBridge;
using Amazon.EventBridge.Model;
using Amazon.Lambda.Core;
using Amazon.Lambda.SQSEvents;
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
    /// Lambda handler for approving properties.
    /// </summary>
    /// <param name="sqsEvent">AWS SQS record. Could contain batch of records.</param>
    /// <param name="context">The context for the Lambda function.</param>
    /// <returns>API Gateway Lambda Proxy Response.</returns>
    [Logging(LogEvent = true, CorrelationIdPath = CorrelationIdPaths.ApiGatewayRest)]
    [Metrics(CaptureColdStart = true)]
    [Tracing(CaptureMode = TracingCaptureMode.ResponseAndError)]
    public async Task FunctionHandler(SQSEvent sqsEvent, ILambdaContext context)
    {
        foreach (var record in sqsEvent.Records)
        {
            string? propertyId = null;

            try
            {
                var request = JsonSerializer.Deserialize<ApprovePublicationRequest>(record.Body);
                propertyId = request.PropertyId ?? "";
                Logger.LogInformation($"Requesting approval for property: {propertyId}");

                // Validate property ID
                if (string.IsNullOrWhiteSpace(propertyId) || !Regex.Match(propertyId, Pattern).Success)
                {
                    Logger.LogCritical($"Input invalid; must conform to regular expression: {Pattern}");
                    return;
                }

                // Parse Property Id functions
                var ddbKeys = PropertyRecordHelper.ParsePropertyId(propertyId);

                Logger.LogInformation($"PK: {ddbKeys["pk"]}, SK: {ddbKeys["sk"]} ");
                
                // Query table for property 
                var properties = await QueryTableAsync(ddbKeys["pk"], ddbKeys["sk"]).ConfigureAwait(false);
                if (!properties.Any())
                {
                    Logger.LogError("No property found in database with the requested property id");
                    return;
                }

                var property = properties.First();

                // Do not approve properties in an approved state
                if (string.Equals(property.Status, PropertyStatus.Approved, StringComparison.CurrentCultureIgnoreCase))
                {
                    Logger.LogWarning($"Property is already {property.Status}; no action taken");
                    return;
                }

                // Publish the event
                await SendEventAsync(propertyId, property).ConfigureAwait(false);

                // Add custom metric for the number of approval requests
                Metrics.AddMetric("ApprovalsRequested", 1, MetricUnit.Count);
                
                Logger.LogInformation($"Stored item in DynamoDB;");
            }
            catch (Exception e)
            {
                Logger.LogError(e);
            }
        } //next Record
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

    /// <summary>
    /// 
    /// </summary>
    /// <param name="propertyId"></param>
    /// <param name="property"></param>
    /// <returns></returns>
    /// <exception cref="Exception"></exception> <summary>
    /// 
    /// </summary>
    /// <param name="propertyId"></param>
    /// <param name="property"></param>
    /// <returns></returns>
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
                Number = property.PropertyNumber,
                Street = property.Street,
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