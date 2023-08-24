// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0
using System;
using System.Collections.Generic;
using System.Net;
using System.Threading.Tasks;
using Amazon.DynamoDBv2.DataModel;
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
        Environment.SetEnvironmentVariable("POWERTOOLS_METRICS_NAMESPACE","ContractService");
    }
    
    [Fact]
    public async Task Create_contract_saves_message_with_new_status()
    {
        // Arrange SQS 
        var request = TestHelpers.LoadApiGatewayProxyRequest("./events/create_valid_event.json");

        var mockDynamoDbContext = Substitute.For<IDynamoDBContext>();
        
        var context = TestHelpers.NewLambdaContext();
        
        var function =
            new CreateContractFunction(mockDynamoDbContext);

        var response = await function.FunctionHandler(request, context);

        await mockPublisher.Received(1).PublishEvent(Arg.Any<Contract>());

        _testOutputHelper.WriteLine("Lambda Response: \n" + response.Body);
        _testOutputHelper.WriteLine("Expected Response: \n" + expectedResponse.Body);

        Assert.Equal(expectedResponse.Headers, response.Headers);
        Assert.Equal(expectedResponse.StatusCode, response.StatusCode);
    }
}