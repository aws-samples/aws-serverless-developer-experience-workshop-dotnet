// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text;
using Amazon.DynamoDBv2.DataModel;
using Amazon.Lambda.APIGatewayEvents;
using Amazon.Lambda.Core;
using Amazon.Lambda.Serialization.SystemTextJson;
using Amazon.Lambda.TestUtilities;

namespace Unicorn.Web.PublicationManagerService.Tests;

public class TestAsyncSearch<T> : AsyncSearch<T>
{
    private readonly List<T> _remainingList;
    
    public TestAsyncSearch(IEnumerable<T> records)
    {
        _remainingList = new List<T>();
        _remainingList.AddRange(records);
    }
    
    public override Task<List<T>> GetRemainingAsync(CancellationToken cancellationToken = new())
    {
        return Task.FromResult(_remainingList);
    }
}

public static class TestHelpers
{
    public static APIGatewayProxyRequest LoadApiGatewayProxyRequest(string filename)
    {
        var serializer = Activator.CreateInstance(typeof(DefaultLambdaJsonSerializer)) as ILambdaSerializer;

        APIGatewayProxyRequest request = null!;
        using var fileStream = LoadJsonTestFile(filename);
        if (serializer != null)
            request = serializer.Deserialize<APIGatewayProxyRequest>(fileStream);

        return request;
    }

    // This utility method takes care of removing the BOM that System.Text.Json doesn't like.
    private static MemoryStream LoadJsonTestFile(string filename)
    {
        var json = File.ReadAllText(filename);
        return new MemoryStream(Encoding.UTF8.GetBytes(json));
    }

    /// <summary>
    /// Creates new Lambda context
    /// </summary>
    /// <returns>TestLambdaContext</returns>
    public static TestLambdaContext NewLambdaContext()
    {
        return new TestLambdaContext
        {
            FunctionName = Guid.NewGuid().ToString("D"),
            FunctionVersion = "1",
            MemoryLimitInMB = 215,
            AwsRequestId = Guid.NewGuid().ToString("D")
        };
    }
    
    public static void SetEnvironmentVariables()
    {
        Environment.SetEnvironmentVariable("DYNAMODB_TABLE", Guid.NewGuid().ToString("D"));
        Environment.SetEnvironmentVariable("EVENT_BUS", Guid.NewGuid().ToString("D"));
        Environment.SetEnvironmentVariable("SERVICE_NAMESPACE", Guid.NewGuid().ToString("D"));
        Environment.SetEnvironmentVariable("POWERTOOLS_SERVICE_NAME", Guid.NewGuid().ToString("D"));
        Environment.SetEnvironmentVariable("POWERTOOLS_TRACE_DISABLED", "true");
        Environment.SetEnvironmentVariable("POWERTOOLS_LOGGER_LOG_EVENT", "false");
        Environment.SetEnvironmentVariable("POWERTOOLS_METRICS_NAMESPACE", Guid.NewGuid().ToString("D"));
        Environment.SetEnvironmentVariable("POWERTOOLS_LOG_LEVEL", "INFO");
    }
    
    public static AsyncSearch<T> NewDynamoDBSearchResult<T>(IEnumerable<T> records)
    {
        return new TestAsyncSearch<T>(records);
    }
}