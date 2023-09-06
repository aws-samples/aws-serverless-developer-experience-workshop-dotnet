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
        Environment.SetEnvironmentVariable("DYNAMODB_TABLE", "uni-prop-local-contract-ContractsTable-1HWB3CU0SJBTQ");
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

        var dynamoDbClient = Substitute.ForPartsOf<AmazonDynamoDBClient>();
        var context = TestHelpers.NewLambdaContext();

        // Act
        var function = new ContractEventHandler(dynamoDbClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert
        await dynamoDbClient.Received(1).PutItemAsync(Arg.Any<PutItemRequest>());
        
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

        var dynamoDbClient = Substitute.ForPartsOf<AmazonDynamoDBClient>();
        var context = TestHelpers.NewLambdaContext();

        // Arrange
        var function = new ContractEventHandler(dynamoDbClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert
        await dynamoDbClient.Received(1).UpdateItemAsync(Arg.Any<UpdateItemRequest>());
    }
}
public class ApiGwSqsPayload
{
    public string property_id { get; set; }
    public address address { get; set; }
    public string seller_name { get; set; }
}

public class address
{
    public int number { get; set; }
    public string? street { get; set; }
    public string? city { get; set; }
    public string country { get; } = "USA";
}
