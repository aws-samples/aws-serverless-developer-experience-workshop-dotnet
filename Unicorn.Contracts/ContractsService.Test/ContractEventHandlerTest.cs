// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Net;
using System.Reflection.Metadata.Ecma335;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Amazon.DynamoDBv2.Model;
using Amazon.Lambda.SQSEvents;
using FizzWare.NBuilder;
using NSubstitute;
using Xunit;
using Xunit.Abstractions;

namespace Unicorn.Contracts.ContractService.Tests;

public class SqsPayload
{
    public string PropertyId { get; set; }
    public Address Address { get; set; }
    public string SellerName { get; set; }
}

[Collection("Sequential")]
public class ContractEventHandlerTest
{
    private readonly ITestOutputHelper _testOutputHelper;

    public ContractEventHandlerTest(ITestOutputHelper testOutputHelper)
    {
        _testOutputHelper = testOutputHelper;

        // Set env variable for Powertools Metrics 
        Environment.SetEnvironmentVariable("POWERTOOLS_METRICS_NAMESPACE", "ContractService");
    }

    [Fact]
    public async Task Create_contract_saves_message_with_new_status()
    {
        // Set up
        var eventPayload = Builder<SqsPayload>.CreateNew()
            .With(x => x.PropertyId = "usa/anytown/main-street/111")
            .With(x => x.Address = new Address() {City = "anytown", Number = 111, Street = "main-street"})
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
                        {
                            "HttpMethod", new SQSEvent.MessageAttribute
                            {
                                StringValue = "POST"
                            }
                        }
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
        await dynamoDbClient.Received(1).PutItemAsync(Arg.Any<PutItemRequest>());
        
    }
}