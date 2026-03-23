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

    [Fact]
    public async Task Create_contract_already_exists_conditional_check_fails_does_not_throw()
    {
        // Arrange
        var eventPayload = Builder<ApiGwSqsPayload>.CreateNew()
            .With(x => x.property_id = "usa/anytown/main-street/888")
            .With(x => x.seller_name = "existing seller")
            .With(x => x.address = new address() { city = "anytown", number = 888, street = "main-street" })
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
            .Returns<PutItemResponse>(_ => throw new ConditionalCheckFailedException("The conditional request failed"));

        var context = TestHelpers.NewLambdaContext();

        // Act - should not throw because ConditionalCheckFailedException is caught
        var function = new ContractEventHandler(mockDynamoDbClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert
        await mockDynamoDbClient.Received(1).PutItemAsync(Arg.Any<PutItemRequest>());
    }

    [Fact]
    public async Task Update_contract_not_in_draft_conditional_check_fails_does_not_throw()
    {
        // Arrange
        var eventPayload = Builder<ApiGwSqsPayload>.CreateNew()
            .With(x => x.property_id = "usa/anytown/main-street/999")
            .With(x => x.seller_name = "any seller")
            .With(x => x.address = new address() { city = "anytown", number = 999, street = "main-street" })
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
            .Returns<UpdateItemResponse>(_ => throw new ConditionalCheckFailedException("The conditional request failed"));

        var context = TestHelpers.NewLambdaContext();

        // Act - should not throw because ConditionalCheckFailedException is caught
        var function = new ContractEventHandler(mockDynamoDbClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert
        await mockDynamoDbClient.Received(1).UpdateItemAsync(Arg.Any<UpdateItemRequest>());
    }

    [Fact]
    public async Task Invalid_http_method_does_not_call_dynamodb()
    {
        // Arrange
        var eventPayload = Builder<ApiGwSqsPayload>.CreateNew()
            .With(x => x.property_id = "usa/anytown/main-street/555")
            .With(x => x.seller_name = "any seller")
            .With(x => x.address = new address() { city = "anytown", number = 555, street = "main-street" })
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
                        { "HttpMethod", new SQSEvent.MessageAttribute { StringValue = "DELETE" } }
                    }
                }
            }
        };

        var mockDynamoDbClient = Substitute.ForPartsOf<AmazonDynamoDBClient>();
        var context = TestHelpers.NewLambdaContext();

        // Act
        var function = new ContractEventHandler(mockDynamoDbClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert - neither PutItem nor UpdateItem should be called
        await mockDynamoDbClient.Received(0).PutItemAsync(Arg.Any<PutItemRequest>());
        await mockDynamoDbClient.Received(0).UpdateItemAsync(Arg.Any<UpdateItemRequest>());
    }

    [Fact]
    public async Task Malformed_sqs_body_throws_exception()
    {
        // Arrange
        var sqsEvent = new SQSEvent()
        {
            Records = new List<SQSEvent.SQSMessage>
            {
                new()
                {
                    Body = "this is not valid json {{{",
                    MessageAttributes = new Dictionary<string, SQSEvent.MessageAttribute>
                    {
                        { "HttpMethod", new SQSEvent.MessageAttribute { StringValue = "POST" } }
                    }
                }
            }
        };

        var mockDynamoDbClient = Substitute.ForPartsOf<AmazonDynamoDBClient>();
        var context = TestHelpers.NewLambdaContext();

        // Act & Assert - malformed JSON in body should cause a deserialization exception
        var function = new ContractEventHandler(mockDynamoDbClient);
        await Assert.ThrowsAsync<System.Text.Json.JsonException>(() => function.FunctionHandler(sqsEvent, context));
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
