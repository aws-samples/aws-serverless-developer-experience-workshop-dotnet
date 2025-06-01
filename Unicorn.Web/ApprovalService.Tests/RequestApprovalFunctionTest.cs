// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json;
using Amazon.DynamoDBv2.DataModel;
using Amazon.EventBridge;
using Amazon.EventBridge.Model;
using Amazon.Lambda.SQSEvents;
using FizzWare.NBuilder;
using NSubstitute;
using Unicorn.Web.Common;
using Xunit;

namespace Unicorn.Web.ApprovalService.Tests;

public class RequestApprovalFunctionTest
{
    public RequestApprovalFunctionTest()
    {
        TestHelpers.SetEnvironmentVariables();
        // Set env variable for Powertools Metrics 
        Environment.SetEnvironmentVariable("POWERTOOLS_METRICS_NAMESPACE", "ContractService");
    }

    [Fact]
    public async Task Publish_event_when_property_status_is_pending_or_declined()
    {
        // Arrange
        var eventPayload = Builder<ApiGwSqsPayload>.CreateNew()
            .With(x => x.PropertyId = "usa/anytown/main-street/777")
            .Build();
        
        var context = TestHelpers.NewLambdaContext();
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();
        var eventBindingClient = Substitute.For<IAmazonEventBridge>();

        var sqsEvent = new SQSEvent()
        {
            Records = new List<SQSEvent.SQSMessage>
            {
                new()
                {
                    Body = JsonSerializer.Serialize(eventPayload)
                }
            }
        };
        
        var searchResult = new List<PropertyRecord>
        {
            new()
            {
                Country = "USA",
                City = "Anytown",
                Street = "Main Street",
                PropertyNumber = "123",
                ListPrice = 2000000.00M,
                Images = new() { "image1.jpg", "image2.jpg", "image3.jpg" },
                Status = PropertyStatus.Pending
            },
            new()
            {
                Country = "USA",
                City = "Anytown",
                Street = "Main Street",
                PropertyNumber = "123",
                ListPrice = 2000000.00M,
                Images = new() { "image1.jpg", "image2.jpg", "image3.jpg" },
                Status = PropertyStatus.Declined
            }
        };

        dynamoDbContext
            .FromQueryAsync<PropertyRecord>(Arg.Any<Amazon.DynamoDBv2.DocumentModel.QueryOperationConfig>())
            .Returns(TestHelpers.NewDynamoDBSearchResult(searchResult));

        eventBindingClient.PutEventsAsync(Arg.Any<PutEventsRequest>(), Arg.Any<CancellationToken>())
            .Returns(new PutEventsResponse { FailedEntryCount = 0 });

        // Act
        var function = new RequestApprovalFunction(dynamoDbContext, eventBindingClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert
        dynamoDbContext.Received(1)
            .FromQueryAsync<PropertyRecord>(Arg.Any<Amazon.DynamoDBv2.DocumentModel.QueryOperationConfig>());

        await eventBindingClient.Received(1)
            .PutEventsAsync(
                Arg.Is<PutEventsRequest>(r => r.Entries.First().DetailType == "PublicationApprovalRequested"),
                Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Do_not_publish_event_when_property_status_is_approved()
    {
        // Arrange
        var eventPayload = Builder<ApiGwSqsPayload>.CreateNew()
            .With(x => x.PropertyId = "usa/anytown/main-street/777")
            .Build();
        var context = TestHelpers.NewLambdaContext();

        var dynamoDbContext = Substitute.For<IDynamoDBContext>();
        var eventBindingClient = Substitute.For<IAmazonEventBridge>();

        var sqsEvent = new SQSEvent()
        {
            Records = new List<SQSEvent.SQSMessage>
            {
                new()
                {
                    Body = JsonSerializer.Serialize(eventPayload)
                }
            }
        };
        
        var searchResult = new List<PropertyRecord>
        {
            new()
            {
                Country = "USA",
                City = "Anytown",
                Street = "Main Street",
                PropertyNumber = "123",
                ListPrice = 2000000.00M,
                Images = new() { "image1.jpg", "image2.jpg", "image3.jpg" },
                Status = PropertyStatus.Approved
            }
        };

        // Act
        var function = new RequestApprovalFunction(dynamoDbContext, eventBindingClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert
        
        dynamoDbContext
            .FromQueryAsync<PropertyRecord>(Arg.Any<Amazon.DynamoDBv2.DocumentModel.QueryOperationConfig>())
            .Returns(TestHelpers.NewDynamoDBSearchResult(searchResult));
        
        dynamoDbContext.Received(1)
            .FromQueryAsync<PropertyRecord>(Arg.Any<Amazon.DynamoDBv2.DocumentModel.QueryOperationConfig>());
        
        eventBindingClient.PutEventsAsync(Arg.Any<PutEventsRequest>(), Arg.Any<CancellationToken>())
            .Returns(new PutEventsResponse { FailedEntryCount = 0 });
            
        await eventBindingClient.Received(0)
            .PutEventsAsync(
                Arg.Is<PutEventsRequest>(r => r.Entries.First().DetailType == "PublicationApprovalRequested"),
                Arg.Any<CancellationToken>());
    }
}

public class ApiGwSqsPayload
{
    public string PropertyId { get; set; }
}