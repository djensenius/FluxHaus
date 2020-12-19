//
//  ContentView.swift
//  Shared
//
//  Created by David Jensenius on 2020-12-13.
//

import SwiftUI


struct ContentView: View {
    @State var date = Date()
    var body: some View {
        VStack(alignment: .trailing) {
            HStack {
                Spacer()
                Text("\(dateString(date: date))")
                    .onAppear(perform: {let _ = self.updateTimer;})
                    .font(.title)
                    .padding(.horizontal)
            }
            HStack {
                Spacer()
                Text("\(timeString(date: date))")
                    .font(.subheadline)
                    .padding(.horizontal)
            }
        }


    }

    var dateFormat: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }

    var timeFormat: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }

    func dateString(date: Date) -> String {
         let time = dateFormat.string(from: date)
         return time
    }

    func timeString(date: Date) -> String {
        let time = timeFormat.string(from: date)
        return time
    }

    var updateTimer: Timer {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true,
                             block: {_ in
                                self.date = Date()
                             })
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
