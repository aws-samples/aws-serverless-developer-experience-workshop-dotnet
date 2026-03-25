// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.Model;
using Amazon.Lambda.SQSEvents;
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

    private static SQSEvent CreateSqsEvent(string body, string httpMethod)
    {
        return new SQSEvent
        {
            Records = new List<SQSEvent.SQSMessage>
            {
                new()
                {
                    Body = body,
                    MessageAttributes = new Dictionary<string, SQSEvent.MessageAttribute>
                    {
                        { "HttpMethod", new SQSEvent.MessageAttribute { StringValue = httpMethod } }
                    }
                }
            }
        };
    }

    [Fact]
    public async Task Create_contract_saves_message_with_new_status()
    {
        // Arrange
        var payload = TestHelpers.LoadPayload("./events/create_contract_valid_1.json");
        var sqsEvent = CreateSqsEvent(payload, "POST");

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
        // Arrange
        var payload = TestHelpers.LoadPayload("./events/update_contract_valid_1.json");
        var sqsEvent = CreateSqsEvent(payload, "PUT");

        var mockDynamoDbClient = Substitute.ForPartsOf<AmazonDynamoDBClient>();
        mockDynamoDbClient.UpdateItemAsync(Arg.Any<UpdateItemRequest>())
            .Returns(new UpdateItemResponse());

        var context = TestHelpers.NewLambdaContext();

        // Act
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
        var payload = TestHelpers.LoadPayload("./events/create_contract_valid_1.json");
        var sqsEvent = CreateSqsEvent(payload, "POST");

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
        var payload = TestHelpers.LoadPayload("./events/update_contract_valid_1.json");
        var sqsEvent = CreateSqsEvent(payload, "PUT");

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
        var payload = TestHelpers.LoadPayload("./events/create_contract_valid_1.json");
        var sqsEvent = CreateSqsEvent(payload, "DELETE");

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
        var sqsEvent = CreateSqsEvent("this is not valid json {{{", "POST");

        var mockDynamoDbClient = Substitute.ForPartsOf<AmazonDynamoDBClient>();
        var context = TestHelpers.NewLambdaContext();

        // Act & Assert - malformed JSON in body should cause a deserialization exception
        var function = new ContractEventHandler(mockDynamoDbClient);
        await Assert.ThrowsAsync<System.Text.Json.JsonException>(() => function.FunctionHandler(sqsEvent, context));
    }
}
