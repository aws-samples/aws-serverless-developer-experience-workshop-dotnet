// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json;
using System.Web;
using Amazon;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Amazon.DynamoDBv2.DocumentModel;
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

namespace Unicorn.Web.SearchService;

public class PropertySearchFunction
{
    private readonly IDynamoDBContext _dynamoDbContext;
    
    /// <summary>
    /// Default constructor. Initialises global variables for function.
    /// </summary>
    /// <exception cref="Exception">Init exception</exception>
    public PropertySearchFunction()
    {
        // Instrument all AWS SDK calls
        AWSSDKHandler.RegisterXRayForAllServices();
        
        var dynamodbTable = Environment.GetEnvironmentVariable("DYNAMODB_TABLE") ?? "";
        if (string.IsNullOrEmpty(dynamodbTable))
            throw new Exception("Environment variable DYNAMODB_TABLE is not defined.");
            
        AWSConfigsDynamoDB.Context.TypeMappings[typeof(PropertyRecord)] =
            new TypeMapping(typeof(PropertyRecord), dynamodbTable);

        var config = new DynamoDBContextConfig { Conversion = DynamoDBEntryConversion.V2 };
        _dynamoDbContext = new DynamoDBContextBuilder()
            .ConfigureContext(c => c.Conversion=DynamoDBEntryConversion.V2)
            .Build();

    }
    
    /// <summary>
    /// Testing constructor for PropertySearchFunction
    /// </summary>
    /// <param name="dynamoDbContext"></param>
    public PropertySearchFunction(IDynamoDBContext dynamoDbContext)
    {
        _dynamoDbContext = dynamoDbContext;
    }

    /// <summary>
    /// Lambda Handler for creating new Contracts.
    /// </summary>
    /// <param name="apigProxyEvent">API Gateway Lambda Proxy Request that triggers the function.</param>
    /// <param name="context">The context for the Lambda function.</param>
    /// <returns>API Gateway Lambda Proxy Response.</returns>
    [Logging(LogEvent = true)]
    [Metrics(CaptureColdStart = true)]
    [Tracing(CaptureMode = TracingCaptureMode.ResponseAndError)]
    public async Task<APIGatewayProxyResponse> FunctionHandler(APIGatewayProxyRequest apigProxyEvent, ILambdaContext context)
    {
        var response = new APIGatewayProxyResponse
        {
            Body = string.Empty,
            StatusCode = 200,
            Headers = new Dictionary<string, string>
            {
                { "Content-Type", "application/json" },
                { "X-Custom-Header", "application/json" }
            }
        };

        if (!string.Equals(apigProxyEvent.HttpMethod, "GET", StringComparison.CurrentCultureIgnoreCase))
        {
            var body = new Dictionary<string, string>
            {
                { "message", "ErrorInRequest" },
                { "requestDetails", "Input Invalid" }
            };
            response.StatusCode = 400;
            response.Body = JsonSerializer.Serialize(body);
            return response;
        }

        try
        {
            var requestPath = (apigProxyEvent.Resource ?? "").ToLower();
            var partitionKey = string.Empty;
            var sortKey = string.Empty;
            switch (requestPath)
            {
                case "/search/{country}/{city}":
                    partitionKey = PropertyRecordHelper.GetPartitionKey
                    (
                        GetPathParameter(apigProxyEvent, "country"),
                        GetPathParameter(apigProxyEvent, "city")
                    );
                    break;
                case "/search/{country}/{city}/{street}":
                    partitionKey = PropertyRecordHelper.GetPartitionKey
                    (
                        GetPathParameter(apigProxyEvent, "country"),
                        GetPathParameter(apigProxyEvent, "city")
                    );
                    sortKey = GetPathParameter(apigProxyEvent, "street").Replace(" ", "-").ToLower();
                    break;
                case "/properties/{country}/{city}/{street}/{number}":
                    partitionKey = PropertyRecordHelper.GetPartitionKey
                    (
                        GetPathParameter(apigProxyEvent, "country"),
                        GetPathParameter(apigProxyEvent, "city")
                    );
                    sortKey = PropertyRecordHelper.GetSortKey(
                        GetPathParameter(apigProxyEvent, "street"),
                        GetPathParameter(apigProxyEvent, "number")
                    );
                    break;
            }

            Logger.LogInformation($"Path is: {requestPath}");
            Logger.LogInformation($"PartitionKey is: {partitionKey} and SortKey is: {sortKey}");

            if (string.IsNullOrEmpty(partitionKey))
            {
                var body = new Dictionary<string, string>
                {
                    { "message", "ErrorInRequest" },
                    { "requestDetails", "Cannot Process Request" }
                };
                response.StatusCode = 500;
                response.Body = JsonSerializer.Serialize(body);
                return response;
            }

            var result = await QueryTableAsync(partitionKey, sortKey).ConfigureAwait(false);
            response.Body = JsonSerializer.Serialize(result.Select(PropertyRecordHelper.ToDto));
        }
        catch (Exception e)
        {
            Logger.LogError(e);
            var body = new Dictionary<string, string>
            {
                { "message", "ErrorInRequest" },
                { "requestDetails", "Cannot Process Request" }
            };
            response.StatusCode = 500;
            response.Body = JsonSerializer.Serialize(body);
        }

        return response;
    }

    private static string GetPathParameter(APIGatewayProxyRequest apigProxyEvent, string parameterName)
    {
        var parameterValue = apigProxyEvent.PathParameters.ContainsKey(parameterName)
            ? apigProxyEvent.PathParameters[parameterName]
            : apigProxyEvent.PathParameters
                .Where(x => string.Equals(x.Key, parameterName, StringComparison.CurrentCultureIgnoreCase))
                .Select(x => x.Value).FirstOrDefault();

        return string.IsNullOrWhiteSpace(parameterValue)
            ? string.Empty
            : HttpUtility.UrlDecode(parameterValue);
    }

    private async Task<List<PropertyRecord>> QueryTableAsync(string partitionKey, string sortKey)
    {
        var filter = new QueryFilter(PropertyNames.PrimaryKey, QueryOperator.Equal, partitionKey);
        if (!string.IsNullOrWhiteSpace(sortKey))
            filter.AddCondition(PropertyNames.SortKey, QueryOperator.BeginsWith, sortKey);
        filter.AddCondition(PropertyNames.Status, QueryOperator.Equal, PropertyStatus.Approved);

        return await _dynamoDbContext
            .FromQueryAsync<PropertyRecord>(new QueryOperationConfig { Filter = filter })
            .GetRemainingAsync()
            .ConfigureAwait(false);
    }
}