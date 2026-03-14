// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.Model;
using Amazon.Lambda.SQSEvents;
using FizzWare.NBuilder;
using NSubstitute;
using Xunit;
using Xunit.Abstractions;

namespace Unicorn.Contracts.ContractService.Tests;

[Collection("Sequential")]
public class ContractEventHandlerTest
{
    private readonly ITestOutputHelper _testOutputHelper;

    public ContractEventHandlerTest(ITestOutputHelper testOutputHelper)
    {
        _testOutputHelper = testOutputHelper;

        // Set env variable for Powertools Metrics 
        Environment.SetEnvironmentVariable("DYNAMODB_TABLE", "uni-prop-local-contract-ContractsTable");
        Environment.SetEnvironmentVariable("POWERTOOLS_METRICS_NAMESPACE", "ContractService");
    }

    [Fact]
    public async Task Create_contract_saves_message_with_new_status()
    {
        // Arrange
        var eventPayload = Builder<ApiGwSqsPayload>.CreateNew()
            .With(x => x.property_id = "usa/anytown/main-street/777")
            .With(x => x.seller_name = "any seller")
            .With(x => x.address = new address() { city = "anytown", number = 777, street = "main-street" })
            .Build();

        var sqsEvent = new SQSEvent()
        {
            Records = new List<SQSEvent.SQSMessage>
            {
                new()
                {
                    Body = JsonSerializer.Serialize(eventPayload),
                    MessageAttributes = new Dictionary<string, SQSEvent.MessageAttribute>
                    {
                        { "HttpMethod", new SQSEvent.MessageAttribute { StringValue = "POST" } }
                    }
                }
            }
        };

        var mockDynamoDbClient = Substitute.ForPartsOf<AmazonDynamoDBClient>();
        mockDynamoDbClient.PutItemAsync(Arg.Any<PutItemRequest>())
            .Returns(new PutItemResponse());

        var context = TestHelpers.NewLambdaContext();

        // Act
        var function = new ContractEventHandler(mockDynamoDbClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert
        await mockDynamoDbClient.Received(1).PutItemAsync(Arg.Any<PutItemRequest>());

    }

    [Fact]
    public async Task Create_contract_with_snake_case_json_populates_all_dynamodb_attributes()
    {
        // Arrange - use snake_case JSON matching the actual API Gateway payload format
        var snakeCaseJson = """
            {
                "address": {
                    "country": "USA",
                    "city": "Anytown",
                    "street": "Main Street",
                    "number": 222
                },
                "seller_name": "John Doe",
                "property_id": "usa/anytown/main-street/222"
            }
            """;

        var sqsEvent = new SQSEvent()
        {
            Records = new List<SQSEvent.SQSMessage>
            {
                new()
                {
                    Body = snakeCaseJson,
                    MessageAttributes = new Dictionary<string, SQSEvent.MessageAttribute>
                    {
                        { "HttpMethod", new SQSEvent.MessageAttribute { StringValue = "POST" } }
                    }
                }
            }
        };

        PutItemRequest? capturedRequest = null;
        var mockDynamoDbClient = Substitute.ForPartsOf<AmazonDynamoDBClient>();
        mockDynamoDbClient.PutItemAsync(Arg.Do<PutItemRequest>(r => capturedRequest = r))
            .Returns(new PutItemResponse());

        var context = TestHelpers.NewLambdaContext();

        // Act
        var function = new ContractEventHandler(mockDynamoDbClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert - verify DynamoDB item has non-empty attribute values
        Assert.NotNull(capturedRequest);
        Assert.False(string.IsNullOrEmpty(capturedRequest.Item["PropertyId"].S),
            "PropertyId should not be null or empty - snake_case 'property_id' must map to PascalCase 'PropertyId'");
        Assert.False(string.IsNullOrEmpty(capturedRequest.Item["SellerName"].S),
            "SellerName should not be null or empty - snake_case 'seller_name' must map to PascalCase 'SellerName'");
        Assert.NotNull(capturedRequest.Item["Address"].M);
        Assert.False(string.IsNullOrEmpty(capturedRequest.Item["Address"].M["City"].S),
            "Address.City should not be null or empty");
        Assert.False(string.IsNullOrEmpty(capturedRequest.Item["Address"].M["Street"].S),
            "Address.Street should not be null or empty");
        Assert.Equal("usa/anytown/main-street/222", capturedRequest.Item["PropertyId"].S);
        Assert.Equal("John Doe", capturedRequest.Item["SellerName"].S);
    }

    [Fact]
    public async Task Update_contract_saves_message_with_new_status()
    {
        // Set up
        var eventPayload = Builder<ApiGwSqsPayload>.CreateNew()
            .With(x => x.property_id = "usa/anytown/main-street/111")
            .With(x => x.seller_name = "any seller")
            .With(x => x.address = new address() { city = "anytown", number = 111, street = "main-street" })
            .Build();

        var sqsEvent = new SQSEvent()
        {
            Records = new List<SQSEvent.SQSMessage>
            {
                new()
                {
                    Body = JsonSerializer.Serialize(eventPayload),
                    MessageAttributes = new Dictionary<string, SQSEvent.MessageAttribute>
                    {
                        { "HttpMethod", new SQSEvent.MessageAttribute { StringValue = "PUT" } }
                    }
                }
            }
        };

        var mockDynamoDbClient = Substitute.ForPartsOf<AmazonDynamoDBClient>();
        mockDynamoDbClient.UpdateItemAsync(Arg.Any<UpdateItemRequest>())
            .Returns(new UpdateItemResponse());
        
        var context = TestHelpers.NewLambdaContext();

        // Arrange
        var function = new ContractEventHandler(mockDynamoDbClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert
        await mockDynamoDbClient.Received(1)
            .UpdateItemAsync(Arg.Any<UpdateItemRequest>());
    }
}

public class ApiGwSqsPayload
{
    public required string property_id { get; set; }
    public required address address { get; set; }
    public required string seller_name { get; set; }
}

public class address
{
    public int number { get; set; }
    public string? street { get; set; }
    public string? city { get; set; }
    public string country { get; } = "USA";
}
