//
//  ContentView.swift
//  zelby-compagnion
//
//  Created by Maxime Dias on 11/07/2024.
//

import SwiftUI

struct ContentView: View {
    @StateObject var manager = HealthManager()
    
    var body: some View {
        VStack {
            Image(systemName: "figure.strengthtraining.traditional")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Fetching todays data!")
        }
        .padding()
        .onAppear {
            manager.fetchHealthData()
        }
    }
}

#Preview {
    ContentView()
}
