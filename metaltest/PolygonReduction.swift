//
//  polygonReduction.swift
//  metaltest
//
//

import Foundation
import Metal
import MetalKit
import simd




class HalfEdgeStructure {
    static func LoadModel(mtlEz: MetalEz, name: String, reduction: Int) -> Model {
        print("load model")
        let model = Model()
        let bodyVtx = mtlEz.loader.loadMesh(name: name).vertexBuffers[0].buffer
        let pOriBuffer = bodyVtx.contents().assumingMemoryBound(to: MeshPoint.self)
        let vertexCount:Int = bodyVtx.length / MemoryLayout<MeshPoint>.size
        print("set half edge", vertexCount)
        for i in 0..<(vertexCount/3) {
            let v0 = pOriBuffer.advanced(by: i * 3 + 0).pointee.point
            var v1 = pOriBuffer.advanced(by: i * 3 + 1).pointee.point
            var v2 = pOriBuffer.advanced(by: i * 3 + 2).pointee.point
            let mynm = cross(float3(v1.x - v0.x, v1.y - v0.y, v1.z - v0.z), float3(v2.x - v0.x, v2.y - v0.y, v2.z - v0.z))
            let ptnm = pOriBuffer.advanced(by: i * 3 + 0).pointee.normal
            let asnm = dot(float3(ptnm.x, ptnm.y, ptnm.z), mynm)
            if asnm < 0 {
                print("chenge vertex")
                let myv = v1
                v1 = v2
                v2 = myv
            }
            model.addPolygon(vertex0: float3(v0.x, v0.y, v0.z),
                             vertex1: float3(v1.x, v1.y, v1.z), vertex2: float3(v2.x, v2.y, v2.z))
        }
        print("update qem all")
        model.updateQuadraticErrorMetricsAll()
        print("reductioning")
        model.polygonReduction(count: reduction)
        return model
    }
}

extension HalfEdgeStructure {
    class HalfEdge {
        var vertex: float3 //始点となる頂点
        private(set) var nextHalfEdge: HalfEdge! //次のハーフエッジ
        private(set) var prevHalfEdge: HalfEdge! //前のハーフエッジ
        var pairHalfEdge: HalfEdge? //稜線を挟んで反対側のハーフエッジ
        var fullEdgeStatus: FullEdge.Status!    //このハーフエッジを含むフルエッジ
        var polygonStatus: Polygon.Status!  //このハーフエッジを含む面
        init(vertex v: float3) {
            vertex = v
        }
        var endVertex: float3 {
            get { return nextHalfEdge.vertex }
            set(v) { nextHalfEdge.vertex = v }
        }
        var startVertex: float3 {
            get { return vertex }
            set(v) { vertex = v }
        }
        func setHalfEdge(next: HalfEdge, prev: HalfEdge) {
            prevHalfEdge = prev
            nextHalfEdge = next
        }
        func repeatPrevHalfEdge(_ action:(HalfEdge) -> Void) {
            var heCK = self.prevHalfEdge.pairHalfEdge!
            repeat {
                action(heCK)
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== self
        }
        func repeatNextHalfEdge(_ action:(HalfEdge) -> Void) {
            var heCK = self.nextHalfEdge.pairHalfEdge!
            repeat {
                action(heCK)
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== self
        }
    }
}

extension HalfEdgeStructure {
    class FullEdge {
        private(set) var uuid: String
        private(set) var leftHalfEdge: HalfEdge! //順方向のハーフエッジ
        private(set) var rightHalfEdge: HalfEdge?    //逆方向のハーフエッジ
        var quadraticErrorMetrics: Double = 0.0 //QEM
        var candidateNewVertex = float3(0, 0, 0)    //QEMを計算した頂点
        init(left: HalfEdge, right: HalfEdge? = nil) {
            uuid = NSUUID().uuidString
            set(left: left)
            if let right = right {
                set(right: right)
                setPairsEachOther()
            }
        }
        func set(left: HalfEdge) {
            leftHalfEdge = left
            left.fullEdgeStatus = Status(uuid: self.uuid, side: .left)
            if rightHalfEdge != nil {
                setPairsEachOther()
            }
        }
        func set(right: HalfEdge) {
            rightHalfEdge = right
            right.fullEdgeStatus = Status(uuid: self.uuid, side: .right)
            setPairsEachOther()
        }
        private func setPairsEachOther() {
            leftHalfEdge.pairHalfEdge = rightHalfEdge
            rightHalfEdge?.pairHalfEdge = leftHalfEdge
        }
        var startVertex: float3 {
            return leftHalfEdge.startVertex
        }
        var endVertex: float3 {
            return leftHalfEdge.endVertex
        }
        struct Status {
            enum Side {
                case right
                case left
            }
            var uuid: String
            var side: Side
        }
        func updateQuadraticErrorMetrics(polygons: inout [String: Polygon]) {
            if self.isAbleToCollapse == false {
                quadraticErrorMetrics = Double.infinity
                return
            }
            var updatePolygonID = [String]()
            leftHalfEdge.repeatPrevHalfEdge{halfEdge in updatePolygonID.append(halfEdge.polygonStatus.uuid)}
            leftHalfEdge.repeatNextHalfEdge{halfEdge in updatePolygonID.append(halfEdge.polygonStatus.uuid)}
            candidateNewVertex = (self.startVertex + self.endVertex) * 0.5
            quadraticErrorMetrics = 0
            for uuid in updatePolygonID.unique {
                if let f = polygons[uuid] {
                    quadraticErrorMetrics += pow(f.distanceBy(point: candidateNewVertex), 2)
                }
            }
        }
        var isAbleToCollapse: Bool {
            guard let leftHalfEdge = self.leftHalfEdge,
                let rightHalfEdge = self.rightHalfEdge  else { return false }
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge,
                let _ = rightHalfEdge.nextHalfEdge.pairHalfEdge, /*heLB*/
                let _ = rightHalfEdge.prevHalfEdge.pairHalfEdge /*heRB*/ else { return false}
            var l_neighborhood = [float3]()
            var r_neighborhood = [float3]()
            var heCK: HalfEdge
            heCK = heLT
            repeat {
                l_neighborhood.append(heCK.endVertex)
                if heCK.prevHalfEdge.pairHalfEdge == nil { return false }
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            heCK = heRT
            repeat {
                r_neighborhood.append(heCK.startVertex)
                if heCK.nextHalfEdge.pairHalfEdge == nil { return false }
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            var cnt: Int = 0
            for l in l_neighborhood {
                for r in r_neighborhood {
                    if l == r { cnt += 1 }
                }
            }
            if cnt >= 3 { return false }
            return true
        }
    }
}
    
extension HalfEdgeStructure {
    class Polygon {
        private(set) var uuid: String
        private(set) var halfEdge: HalfEdge  //含むハーフエッジの１つ
        struct Status {
            var uuid: String
        }
        init(halfEdge h: HalfEdge) {
            uuid = NSUUID().uuidString
            halfEdge = h
            var he = halfEdge
            repeat {
                he.polygonStatus = Status(uuid: self.uuid)
                he = he.nextHalfEdge
            } while he !== halfEdge
        }
        private var equation: float4 {
            let v0 = halfEdge.vertex
            let v1 = halfEdge.nextHalfEdge.vertex
            let v2 = halfEdge.prevHalfEdge.vertex
            let c = cross(v1 - v0, v2 - v0)
            let d = -1 * dot(v0, c)
            return float4(c.x, c.y, c.z, d)
        }
        func distanceBy(point: float3) -> Double {
            return Double(dot(self.equation, point.toFloat4))
        }
    }
}
    
extension HalfEdgeStructure {
    class Model {
        private(set) var polygons: [String: Polygon]
        private(set) var fullEdges: [String: FullEdge]
        init() {
            polygons = [String: Polygon]()
            fullEdges = [String: FullEdge]()
        }
        private func setPair(halfEdges targetHalfEdges: HalfEdge...) { //ペアのハーフエッジを設定する
            for targetHalfEdge in targetHalfEdges {
                var flag: Bool = false
                for (_, fullEdge) in fullEdges {
                    if fullEdge.startVertex == targetHalfEdge.endVertex && fullEdge.endVertex == targetHalfEdge.startVertex {
                        fullEdge.set(right: targetHalfEdge)
                        flag = true
                        break
                    }
                }
                if flag == false {
                    let fe = FullEdge(left: targetHalfEdge)
                    fullEdges[fe.uuid] = fe
                }
            }
        }
        func addPolygon(vertex0: float3, vertex1: float3, vertex2: float3) {
            print("add polygon")
            let he0 = HalfEdge(vertex: vertex0)
            let he1 = HalfEdge(vertex: vertex1)
            let he2 = HalfEdge(vertex: vertex2)
            he0.setHalfEdge(next: he1, prev: he2)
            he1.setHalfEdge(next: he2, prev: he0)
            he2.setHalfEdge(next: he0, prev: he1)
            let polygon = Polygon(halfEdge: he0)
            polygons[polygon.uuid] = polygon
            setPair(halfEdges: he0, he1, he2)
        }
        func updateQuadraticErrorMetricsAll() {
            for (_, fullEdge) in fullEdges {
                fullEdge.updateQuadraticErrorMetrics(polygons: &polygons)
            }
        }
        func updateQuadraticErrorMetrics(uuids: [String]) {
            for uuid in uuids {
                if let f = fullEdges[uuid] {
                    f.updateQuadraticErrorMetrics(polygons: &polygons)
                }
            }
        }
        private func collapse(fullEdge: FullEdge) {
            print("edgeCollapse")
            if fullEdge.isAbleToCollapse == false {
                fullEdge.quadraticErrorMetrics = Double.infinity
                return
            }
            guard let leftHalfEdge = fullEdge.leftHalfEdge,
                let rightHalfEdge = fullEdge.rightHalfEdge  else { return }
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge,
                let heLB = rightHalfEdge.nextHalfEdge.pairHalfEdge,
                let heRB = rightHalfEdge.prevHalfEdge.pairHalfEdge else { return}
            
            var updatedHalfEdge = [String]()
            leftHalfEdge.repeatPrevHalfEdge{halfEdge in
                halfEdge.startVertex = fullEdge.candidateNewVertex
                updatedHalfEdge.append(halfEdge.fullEdgeStatus.uuid)
            }
            leftHalfEdge.repeatNextHalfEdge{halfEdge in
                halfEdge.endVertex = fullEdge.candidateNewVertex
                updatedHalfEdge.append(halfEdge.fullEdgeStatus.uuid)
            }
            
            for id in [fullEdge.uuid, heRT.fullEdgeStatus.uuid, heLT.fullEdgeStatus.uuid,
                       heLB.fullEdgeStatus.uuid, heRB.fullEdgeStatus.uuid] {
                        fullEdges.removeValue(forKey: id)
                        updatedHalfEdge.remove(value: id)
            }
            
            let fe0 = FullEdge(left: heRT, right: heLT)
            let fe1 = FullEdge(left: heLB, right: heRB)
            fullEdges[fe0.uuid] = fe0
            fullEdges[fe1.uuid] = fe1
            
            updatedHalfEdge.append(fe0.uuid)
            updatedHalfEdge.append(fe1.uuid)
            
            polygons.removeValue(forKey: leftHalfEdge.polygonStatus.uuid)
            polygons.removeValue(forKey: rightHalfEdge.polygonStatus.uuid)
            
            self.updateQuadraticErrorMetrics(uuids: updatedHalfEdge.unique)
            return
        }
        func polygonReduction(count: Int) {
            for _ in 0..<(count / 2) {
                let v = fullEdges.min(by: {a, b in a.value.quadraticErrorMetrics < b.value.quadraticErrorMetrics} )
                if let f = v?.value {
                    collapse(fullEdge: f)
                }
            }
        }
    }
}




extension HalfEdgeStructure {
    struct myfloat4 {
        var x: Float
        var y: Float
        var z: Float
        var w: Float
    }
    struct myfloat3 {
        var x: Float
        var y: Float
        var z: Float
    }
    struct myfloat2 {
        var x: Float
        var y: Float
    }
    struct MeshPoint {
        var point: myfloat3
        var normal: myfloat3
        var texcoord: myfloat2
    }
}


extension Array where Element: Equatable {
    var unique: [Element] {
        return reduce([Element]()) { $0.contains($1) ? $0 : $0 + [$1] }
    }
    mutating func remove(value: Element) {
        if let i = self.index(of: value) {
            self.remove(at: i)
        }
    }
}




/*

class HalfEdgeController {
    class HalfEdge {
        var vertex: float3 //始点となる頂点
        var nextHalfEdge: HalfEdge! //次のハーフエッジ
        var prevHalfEdge: HalfEdge! //前のハーフエッジ
        var pairHalfEdge: HalfEdge? //稜線を挟んで反対側のハーフエッジ
        var fullEdgeStatus: FullEdge.Status!
        var polygonStatus: Polygon.Status!
        init(vertex v: float3) {
            vertex = v
        }
        var endVertex: float3 {
            get { return nextHalfEdge.vertex }
            set(v) { nextHalfEdge.vertex = v }
        }
        var startVertex: float3 {
            get { return vertex }
            set(v) { vertex = v }
        }
        func setHalfEdge(next: HalfEdge, prev: HalfEdge) {
            prevHalfEdge = prev
            nextHalfEdge = next
        }
        func repeatPrevHalfEdge(_ action:(HalfEdge) -> Void) {
            var heCK = self.prevHalfEdge.pairHalfEdge!
            repeat {
                action(heCK)
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== self
        }
        func repeatNextHalfEdge(_ action:(HalfEdge) -> Void) {
            var heCK = self.nextHalfEdge.pairHalfEdge!
            repeat {
                action(heCK)
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== self
        }
    }
    class FullEdge {
        var uuid: String
        var leftHalfEdge: HalfEdge! //順方向のハーフエッジ
        var rightHalfEdge: HalfEdge?    //逆方向のハーフエッジ
        var quadraticErrorMetrics: Double = 0.0
        var candidateNewVertex = float3(0, 0, 0)
        init(left: HalfEdge, right: HalfEdge? = nil) {
            uuid = NSUUID().uuidString
            set(left: left)
            if let right = right {
                set(right: right)
                setPairsEachOther()
            }
        }
        func set(left: HalfEdge) {
            leftHalfEdge = left
            left.fullEdgeStatus = Status(uuid: self.uuid, side: .left)
            if rightHalfEdge != nil {
                setPairsEachOther()
            }
        }
        func set(right: HalfEdge) {
            rightHalfEdge = right
            right.fullEdgeStatus = Status(uuid: self.uuid, side: .right)
            setPairsEachOther()
        }
        func setPairsEachOther() {
            leftHalfEdge.pairHalfEdge = rightHalfEdge
            rightHalfEdge?.pairHalfEdge = leftHalfEdge
        }
        var startVertex: float3 {
            return leftHalfEdge.startVertex
        }
        var endVertex: float3 {
            return leftHalfEdge.endVertex
        }
        struct Status {
            enum Side {
                case right
                case left
            }
            var uuid: String
            var side: Side
        }
        func updateQuadraticErrorMetrics(polygons: inout [String: Polygon]) {
            if self.isAbleToCollapse == false {
                quadraticErrorMetrics = Double.infinity
                return
            }
            var updatePolygonID = [String]()
            leftHalfEdge.repeatPrevHalfEdge{halfEdge in updatePolygonID.append(halfEdge.polygonStatus.uuid)}
            leftHalfEdge.repeatNextHalfEdge{halfEdge in updatePolygonID.append(halfEdge.polygonStatus.uuid)}
            candidateNewVertex = (self.startVertex + self.endVertex) * 0.5
            quadraticErrorMetrics = 0
            for uuid in updatePolygonID.unique {
                if let f = polygons[uuid] {
                    quadraticErrorMetrics += pow(f.distanceBy(point: candidateNewVertex), 2)
                }
            }
        }
        var isAbleToCollapse: Bool {
            guard let leftHalfEdge = self.leftHalfEdge,
                let rightHalfEdge = self.rightHalfEdge  else { return false }
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge,
                let _ = rightHalfEdge.nextHalfEdge.pairHalfEdge, /*heLB*/
                let _ = rightHalfEdge.prevHalfEdge.pairHalfEdge /*heRB*/ else { return false}
            var l_neighborhood = [float3]()
            var r_neighborhood = [float3]()
            var heCK: HalfEdge
            heCK = heLT
            repeat {
                l_neighborhood.append(heCK.endVertex)
                if heCK.prevHalfEdge.pairHalfEdge == nil { return false }
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            heCK = heRT
            repeat {
                r_neighborhood.append(heCK.startVertex)
                if heCK.nextHalfEdge.pairHalfEdge == nil { return false }
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            var cnt: Int = 0
            for l in l_neighborhood {
                for r in r_neighborhood {
                    if l == r { cnt += 1 }
                }
            }
            if cnt >= 3 { return false }
            return true
        }
    }
    
    class Polygon {
        var uuid: String
        var halfEdge: HalfEdge  //含むハーフエッジの１つ
        struct Status {
            var uuid: String
        }
        init(halfEdge h: HalfEdge) {
            uuid = NSUUID().uuidString
            halfEdge = h
            var he = halfEdge
            repeat {
                he.polygonStatus = Status(uuid: self.uuid)
                he = he.nextHalfEdge
            } while he !== halfEdge
        }
        var equation: float4 {
            let v0 = halfEdge.vertex
            let v1 = halfEdge.nextHalfEdge.vertex
            let v2 = halfEdge.prevHalfEdge.vertex
            let c = cross(v1 - v0, v2 - v0)
            let d = -1 * dot(v0, c)
            return float4(c.x, c.y, c.z, d)
        }
        func distanceBy(point: float3) -> Double {
            return Double(dot(self.equation, point.toFloat4))
        }
    }
    
    class Model {
        var polygons: [String: Polygon]
        var fullEdges: [String: FullEdge]
        init() {
            polygons = [String: Polygon]()
            fullEdges = [String: FullEdge]()
        }
        private func setPair(halfEdges targetHalfEdges: HalfEdge...) { //ペアのハーフエッジを設定する
            for targetHalfEdge in targetHalfEdges {
                var flag: Bool = false
                for (_, fullEdge) in fullEdges {
                    if fullEdge.startVertex == targetHalfEdge.endVertex && fullEdge.endVertex == targetHalfEdge.startVertex {
                        fullEdge.set(right: targetHalfEdge)
                        flag = true
                        break
                    }
                }
                if flag == false {
                    let fe = FullEdge(left: targetHalfEdge)
                    fullEdges[fe.uuid] = fe
                }
            }
        }
        func addPolygon(vertex0: float3, vertex1: float3, vertex2: float3) {
            print("add polygon")
            let he0 = HalfEdge(vertex: vertex0)
            let he1 = HalfEdge(vertex: vertex1)
            let he2 = HalfEdge(vertex: vertex2)
            he0.setHalfEdge(next: he1, prev: he2)
            he1.setHalfEdge(next: he2, prev: he0)
            he2.setHalfEdge(next: he0, prev: he1)
            let polygon = Polygon(halfEdge: he0)
            polygons[polygon.uuid] = polygon
            setPair(halfEdges: he0, he1, he2)
        }
        func updateQuadraticErrorMetricsAll() {
            for (_, fullEdge) in fullEdges {
                fullEdge.updateQuadraticErrorMetrics(polygons: &polygons)
            }
        }
        func updateQuadraticErrorMetrics(uuids: [String]) {
            for uuid in uuids {
                if let f = fullEdges[uuid] {
                    f.updateQuadraticErrorMetrics(polygons: &polygons)
                }
            }
        }
        
        func collapse(fullEdge: FullEdge) {
            print("edgeCollapse")
            if fullEdge.isAbleToCollapse == false {
                fullEdge.quadraticErrorMetrics = Double.infinity
                return
            }
            guard let leftHalfEdge = fullEdge.leftHalfEdge,
                let rightHalfEdge = fullEdge.rightHalfEdge  else { return }
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge,
                let heLB = rightHalfEdge.nextHalfEdge.pairHalfEdge,
                let heRB = rightHalfEdge.prevHalfEdge.pairHalfEdge else { return}
            
            var updatedHalfEdge = [String]()
            leftHalfEdge.repeatPrevHalfEdge{halfEdge in
                halfEdge.startVertex = fullEdge.candidateNewVertex
                updatedHalfEdge.append(halfEdge.fullEdgeStatus.uuid)
            }
            leftHalfEdge.repeatNextHalfEdge{halfEdge in
                halfEdge.endVertex = fullEdge.candidateNewVertex
                updatedHalfEdge.append(halfEdge.fullEdgeStatus.uuid)
            }
            
            for id in [fullEdge.uuid, heRT.fullEdgeStatus.uuid, heLT.fullEdgeStatus.uuid,
                       heLB.fullEdgeStatus.uuid, heRB.fullEdgeStatus.uuid] {
                        fullEdges.removeValue(forKey: id)
                        updatedHalfEdge.remove(value: id)
            }
            
            let fe0 = FullEdge(left: heRT, right: heLT)
            let fe1 = FullEdge(left: heLB, right: heRB)
            fullEdges[fe0.uuid] = fe0
            fullEdges[fe1.uuid] = fe1
            
            updatedHalfEdge.append(fe0.uuid)
            updatedHalfEdge.append(fe1.uuid)
            
            polygons.removeValue(forKey: leftHalfEdge.polygonStatus.uuid)
            polygons.removeValue(forKey: rightHalfEdge.polygonStatus.uuid)
            
            self.updateQuadraticErrorMetrics(uuids: updatedHalfEdge.unique)
            return
        }
        func polygonReduction(count: Int) {
            for _ in 0..<(count / 2) {
                let v = fullEdges.min(by: {a, b in a.value.quadraticErrorMetrics < b.value.quadraticErrorMetrics} )
                if let f = v?.value {
                    collapse(fullEdge: f)
                }
            }
        }
    }
    
    static func LoadModel(mtlEz: MetalEz, name: String, reduction: Int) -> Model {
        print("load model")
        let model = Model()
        let bodyVtx = mtlEz.loader.loadMesh(name: name).vertexBuffers[0].buffer
        let pOriBuffer = bodyVtx.contents().assumingMemoryBound(to: MeshPoint.self)
        let vertexCount:Int = bodyVtx.length / MemoryLayout<MeshPoint>.size
        print("set half edge", vertexCount)
        for i in 0..<(vertexCount/3) {
            let v0 = pOriBuffer.advanced(by: i * 3 + 0).pointee.point
            var v1 = pOriBuffer.advanced(by: i * 3 + 1).pointee.point
            var v2 = pOriBuffer.advanced(by: i * 3 + 2).pointee.point
            //            print("point is ", v0, v1, v2)
            let mynm = cross(float3(v1.x - v0.x, v1.y - v0.y, v1.z - v0.z), float3(v2.x - v0.x, v2.y - v0.y, v2.z - v0.z))
            let ptnm = pOriBuffer.advanced(by: i * 3 + 0).pointee.normal
            let asnm = dot(float3(ptnm.x, ptnm.y, ptnm.z), mynm)
            if asnm < 0 {
                print("chenge vertex")
                let myv = v1
                v1 = v2
                v2 = myv
            }
            model.addPolygon(vertex0: float3(v0.x, v0.y, v0.z),
                             vertex1: float3(v1.x, v1.y, v1.z), vertex2: float3(v2.x, v2.y, v2.z))
        }
        print("update qem all")
        model.updateQuadraticErrorMetricsAll()
        print("reductioning")
        model.polygonReduction(count: reduction)
        return model
    }
    
}

extension Array where Element: Equatable {
    var unique: [Element] {
        return reduce([Element]()) { $0.contains($1) ? $0 : $0 + [$1] }
    }
    mutating func remove(value: Element) {
        if let i = self.index(of: value) {
            self.remove(at: i)
        }
    }
}

*/







/*
class HalfEdgeController {
    class HalfEdge {
        var vertex: float3 //始点となる頂点
        var nextHalfEdge: HalfEdge! //次のハーフエッジ
        var prevHalfEdge: HalfEdge! //前のハーフエッジ
        var pairHalfEdge: HalfEdge? //稜線を挟んで反対側のハーフエッジ
        var fullEdgeStatus: FullEdge.Status!
        var faceStatus: Face.Status!
        init(vertex v: float3) {
            vertex = v
        }
        var endVertex: float3 {
            get { return nextHalfEdge.vertex }
            set(v) { nextHalfEdge.vertex = v }
        }
        var startVertex: float3 {
            get { return vertex }
            set(v) { vertex = v }
        }
        func setHalfEdge(next: HalfEdge, prev: HalfEdge) {
            prevHalfEdge = prev
            nextHalfEdge = next
        }
        func repeatPrevHalfEdge(_ action:(HalfEdge) -> Void) {
            var heCK = self.prevHalfEdge.pairHalfEdge!
            repeat {
                action(heCK)
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== self
        }
        func repeatNextHalfEdge(_ action:(HalfEdge) -> Void) {
            var heCK = self.nextHalfEdge.pairHalfEdge!
            repeat {
                action(heCK)
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== self
        }
    }
    class FullEdge {
        var uuid: String
        var leftHalfEdge: HalfEdge! //順方向のハーフエッジ
        var rightHalfEdge: HalfEdge?    //逆方向のハーフエッジ
        var quadraticErrorMetrics: Double = 0.0
        var candidateNewVertex = float3(0, 0, 0)
        init(left: HalfEdge, right: HalfEdge? = nil) {
            uuid = NSUUID().uuidString
            set(left: left)
            if let right = right {
                set(right: right)
                setPairsEachOther()
            }
        }
        func set(left: HalfEdge) {
            leftHalfEdge = left
            left.fullEdgeStatus = Status(uuid: self.uuid, side: .left)
            if rightHalfEdge != nil {
                setPairsEachOther()
            }
        }
        func set(right: HalfEdge) {
            rightHalfEdge = right
            right.fullEdgeStatus = Status(uuid: self.uuid, side: .right)
            setPairsEachOther()
        }
        func setPairsEachOther() {
            leftHalfEdge.pairHalfEdge = rightHalfEdge
            rightHalfEdge?.pairHalfEdge = leftHalfEdge
        }
        var startVertex: float3 {
            return leftHalfEdge.startVertex
        }
        var endVertex: float3 {
            return leftHalfEdge.endVertex
        }
        struct Status {
            enum Side {
                case right
                case left
            }
            var uuid: String
            var side: Side
        }
        func updateQuadraticErrorMetrics(faces: inout [String: Face]) {
            if self.isAbleToCollapse == false {
                quadraticErrorMetrics = Double.infinity
                return
            }
            var updateFaceID = [String]()
            leftHalfEdge.repeatPrevHalfEdge{halfEdge in updateFaceID.append(halfEdge.faceStatus.uuid)}
            leftHalfEdge.repeatNextHalfEdge{halfEdge in updateFaceID.append(halfEdge.faceStatus.uuid)}
            candidateNewVertex = (self.startVertex + self.endVertex) * 0.5
            quadraticErrorMetrics = 0
            for uuid in updateFaceID.unique {
                if let f = faces[uuid] {
                    quadraticErrorMetrics += pow(f.distanceBy(point: candidateNewVertex), 2)
                }
            }
        }
        var isAbleToCollapse: Bool {
            guard let leftHalfEdge = self.leftHalfEdge,
                let rightHalfEdge = self.rightHalfEdge  else { return false }
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge,
                let _ = rightHalfEdge.nextHalfEdge.pairHalfEdge, /*heLB*/
                let _ = rightHalfEdge.prevHalfEdge.pairHalfEdge /*heRB*/ else { return false}
            var l_neighborhood = [float3]()
            var r_neighborhood = [float3]()
            var heCK: HalfEdge
            heCK = heLT
            repeat {
                l_neighborhood.append(heCK.endVertex)
                if heCK.prevHalfEdge.pairHalfEdge == nil { return false }
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            heCK = heRT
            repeat {
                r_neighborhood.append(heCK.startVertex)
                if heCK.nextHalfEdge.pairHalfEdge == nil { return false }
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            var cnt: Int = 0
            for l in l_neighborhood {
                for r in r_neighborhood {
                    if l == r { cnt += 1 }
                }
            }
            if cnt >= 3 { return false }
            return true
        }
    }
    
    class Face {
        var uuid: String
        var halfEdge: HalfEdge  //含むハーフエッジの１つ
        struct Status {
            var uuid: String
        }
        init(halfEdge h: HalfEdge) {
            uuid = NSUUID().uuidString
            halfEdge = h
            var he = halfEdge
            repeat {
                he.faceStatus = Status(uuid: self.uuid)
                he = he.nextHalfEdge
            } while he !== halfEdge
        }
        var equation: float4 {
            let v0 = halfEdge.vertex
            let v1 = halfEdge.nextHalfEdge.vertex
            let v2 = halfEdge.prevHalfEdge.vertex
            let c = cross(v1 - v0, v2 - v0)
            let d = -1 * dot(v0, c)
            return float4(c.x, c.y, c.z, d)
        }
        func distanceBy(point: float3) -> Double {
            return Double(dot(self.equation, point.toFloat4))
        }
    }
    
    class Model {
        var faces: [String: Face]
        var fullEdges: [String: FullEdge]
        init() {
            faces = [String: Face]()
            fullEdges = [String: FullEdge]()
        }
        private func setPair(halfEdges targetHalfEdges: HalfEdge...) { //ペアのハーフエッジを設定する
            for targetHalfEdge in targetHalfEdges {
                var flag: Bool = false
                for (_, fullEdge) in fullEdges {
                    if fullEdge.startVertex == targetHalfEdge.endVertex && fullEdge.endVertex == targetHalfEdge.startVertex {
                        fullEdge.set(right: targetHalfEdge)
                        flag = true
                        break
                    }
                }
                if flag == false {
                    let fe = FullEdge(left: targetHalfEdge)
                    fullEdges[fe.uuid] = fe
                }
            }
        }
        func addFace(vertex0: float3, vertex1: float3, vertex2: float3) {
            print("add face")
            let he0 = HalfEdge(vertex: vertex0)
            let he1 = HalfEdge(vertex: vertex1)
            let he2 = HalfEdge(vertex: vertex2)
            he0.setHalfEdge(next: he1, prev: he2)
            he1.setHalfEdge(next: he2, prev: he0)
            he2.setHalfEdge(next: he0, prev: he1)
            let face = Face(halfEdge: he0)
            faces[face.uuid] = face
            setPair(halfEdges: he0, he1, he2)
        }
        func updateQuadraticErrorMetricsAll() {
            for (_, fullEdge) in fullEdges {
                fullEdge.updateQuadraticErrorMetrics(faces: &faces)
            }
        }
        func updateQuadraticErrorMetrics(uuids: [String]) {
            for uuid in uuids {
                if let f = fullEdges[uuid] {
                    f.updateQuadraticErrorMetrics(faces: &faces)
                }
            }
        }
        
        func collapse(fullEdge: FullEdge) {
            print("edgeCollapse")
            if fullEdge.isAbleToCollapse == false {
                fullEdge.quadraticErrorMetrics = Double.infinity
                return
            }
            guard let leftHalfEdge = fullEdge.leftHalfEdge,
                let rightHalfEdge = fullEdge.rightHalfEdge  else { return }
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge,
                let heLB = rightHalfEdge.nextHalfEdge.pairHalfEdge,
                let heRB = rightHalfEdge.prevHalfEdge.pairHalfEdge else { return}
            
            var updatedHalfEdge = [String]()
            leftHalfEdge.repeatPrevHalfEdge{halfEdge in
                halfEdge.startVertex = fullEdge.candidateNewVertex
                updatedHalfEdge.append(halfEdge.fullEdgeStatus.uuid)
            }
            leftHalfEdge.repeatNextHalfEdge{halfEdge in
                halfEdge.endVertex = fullEdge.candidateNewVertex
                updatedHalfEdge.append(halfEdge.fullEdgeStatus.uuid)
            }
            
            func deleteFullEdges(uuids: String...) {
                for id in uuids {
                    fullEdges.removeValue(forKey: id)
                    updatedHalfEdge.remove(value: id)
                }
            }
            deleteFullEdges(uuids: fullEdge.uuid, heRT.fullEdgeStatus.uuid, heLT.fullEdgeStatus.uuid,
                            heLB.fullEdgeStatus.uuid, heRB.fullEdgeStatus.uuid)
            
            let fe0 = FullEdge(left: heRT, right: heLT)
            let fe1 = FullEdge(left: heLB, right: heRB)
            fullEdges[fe0.uuid] = fe0
            fullEdges[fe1.uuid] = fe1
            
            updatedHalfEdge.append(fe0.uuid)
            updatedHalfEdge.append(fe1.uuid)
            
            faces.removeValue(forKey: leftHalfEdge.faceStatus.uuid)
            faces.removeValue(forKey: rightHalfEdge.faceStatus.uuid)
            
            self.updateQuadraticErrorMetrics(uuids: updatedHalfEdge.unique)
            return
        }
        func polygonReduction(count: Int) {
            for _ in 0..<(count / 2) {
                let v = fullEdges.min(by: {a, b in a.value.quadraticErrorMetrics < b.value.quadraticErrorMetrics} )
                if let f = v?.value {
                    collapse(fullEdge: f)
                }
            }
        }
    }
    
    static func LoadModel(mtlEz: MetalEz, name: String, reduction: Int) -> Model {
        print("load model")
        let model = Model()
        let bodyVtx = mtlEz.loader.loadMesh(name: name).vertexBuffers[0].buffer
        let pOriBuffer = bodyVtx.contents().assumingMemoryBound(to: MeshPoint.self)
        let vertexCount:Int = bodyVtx.length / MemoryLayout<MeshPoint>.size
        print("set half edge", vertexCount)
        for i in 0..<(vertexCount/3) {
            let v0 = pOriBuffer.advanced(by: i * 3 + 0).pointee.point
            var v1 = pOriBuffer.advanced(by: i * 3 + 1).pointee.point
            var v2 = pOriBuffer.advanced(by: i * 3 + 2).pointee.point
            //            print("point is ", v0, v1, v2)
            let mynm = cross(float3(v1.x - v0.x, v1.y - v0.y, v1.z - v0.z), float3(v2.x - v0.x, v2.y - v0.y, v2.z - v0.z))
            let ptnm = pOriBuffer.advanced(by: i * 3 + 0).pointee.normal
            let asnm = dot(float3(ptnm.x, ptnm.y, ptnm.z), mynm)
            if asnm < 0 {
                print("chenge vertex")
                let myv = v1
                v1 = v2
                v2 = myv
            }
            model.addFace(vertex0: float3(v0.x, v0.y, v0.z), vertex1: float3(v1.x, v1.y, v1.z), vertex2: float3(v2.x, v2.y, v2.z))
        }
        print("update qem all")
        model.updateQuadraticErrorMetricsAll()
        print("reductioning")
        model.polygonReduction(count: reduction)
        return model
    }
    
}

extension Array where Element: Equatable {
    var unique: [Element] {
        return reduce([Element]()) { $0.contains($1) ? $0 : $0 + [$1] }
    }
    mutating func remove(value: Element) {
        if let i = self.index(of: value) {
            self.remove(at: i)
        }
    }
}



*/

/*

class HalfEdgeController {
    class HalfEdge {
        var vertex: float3 //始点となる頂点
        var nextHalfEdge: HalfEdge! //次のハーフエッジ
        var prevHalfEdge: HalfEdge! //前のハーフエッジ
        var pairHalfEdge: HalfEdge? //稜線を挟んで反対側のハーフエッジ
        var fullEdgeStatus: FullEdge.Status!
        var faceStatus: Face.Status!
        init(vertex v: float3) {
            vertex = v
        }
        var endVertex: float3 {
            get { return nextHalfEdge.vertex }
            set(v) { nextHalfEdge.vertex = v }
        }
        var startVertex: float3 {
            get { return vertex }
            set(v) { vertex = v }
        }
        func setHalfEdge(next: HalfEdge, prev: HalfEdge) {
            prevHalfEdge = prev
            nextHalfEdge = next
        }
        func repeatPrevHalfEdge(_ action:(HalfEdge) -> Void) {
            var heCK = self.prevHalfEdge.pairHalfEdge!
            repeat {
                action(heCK)
                //                updateFaceID[heCK.faceStatus.uuid] = true
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== self
        }
        func repeatNextHalfEdge(_ action:(HalfEdge) -> Void) {
            var heCK = self.nextHalfEdge.pairHalfEdge!
            repeat {
                action(heCK)
                //                updateFaceID[heCK.faceStatus.uuid] = true
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== self
        }
    }
    class FullEdge {
        var uuid: String
        var leftHalfEdge: HalfEdge! //順方向のハーフエッジ
        var rightHalfEdge: HalfEdge?    //逆方向のハーフエッジ
        var quadraticErrorMetrics: Double = 0.0
        var candidateNewVertex = float3(0, 0, 0)
        init(left: HalfEdge, right: HalfEdge? = nil) {
            uuid = NSUUID().uuidString
            set(left: left)
            if let right = right {
                set(right: right)
                setPairsEachOther()
            }
        }
        func set(left: HalfEdge) {
            leftHalfEdge = left
            left.fullEdgeStatus = Status(uuid: self.uuid, side: .left)
            if rightHalfEdge != nil {
                setPairsEachOther()
            }
        }
        func set(right: HalfEdge) {
            rightHalfEdge = right
            right.fullEdgeStatus = Status(uuid: self.uuid, side: .right)
            setPairsEachOther()
        }
        func setPairsEachOther() {
            leftHalfEdge.pairHalfEdge = rightHalfEdge
            rightHalfEdge?.pairHalfEdge = leftHalfEdge
        }
        var startVertex: float3 {
            return leftHalfEdge.startVertex
        }
        var endVertex: float3 {
            return leftHalfEdge.endVertex
        }
        struct Status {
            enum Side {
                case right
                case left
            }
            var uuid: String
            var side: Side
        }
        func updateQuadraticErrorMetrics(faces: inout [String: Face]) {
            if self.isAbleToCollapse == false {
                quadraticErrorMetrics = Double.infinity
                return
            }
            var updateFaceID = [String: Bool]()
            guard let leftHalfEdge = self.leftHalfEdge else { return }
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge else { return }
            
            /*            var heCK: HalfEdge
             heCK = heLT
             repeat {
             updateFaceID[heCK.faceStatus.uuid] = true
             heCK = heCK.prevHalfEdge.pairHalfEdge!
             } while heCK !== self.leftHalfEdge
             heCK = heRT
             repeat {
             updateFaceID[heCK.faceStatus.uuid] = true
             heCK = heCK.nextHalfEdge.pairHalfEdge!
             } while heCK !== self.leftHalfEdge*/
            
            leftHalfEdge.repeatPrevHalfEdge{halfEdge in updateFaceID[halfEdge.faceStatus.uuid] = true}
            leftHalfEdge.repeatNextHalfEdge{halfEdge in updateFaceID[halfEdge.faceStatus.uuid] = true}
            
            candidateNewVertex = (self.startVertex + self.endVertex) * 0.5
            quadraticErrorMetrics = 0
            for (key, _) in updateFaceID {
                if let f = faces[key] {
                    quadraticErrorMetrics += pow(f.distanceBy(point: candidateNewVertex), 2)
                }
            }
        }
        var isAbleToCollapse: Bool {
            guard let leftHalfEdge = self.leftHalfEdge else { return false }
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge else { return false }
            var l_neighborhood = [float3]()
            var r_neighborhood = [float3]()
            var heCK: HalfEdge
            heCK = heLT
            repeat {
                l_neighborhood.append(heCK.endVertex)
                if heCK.prevHalfEdge.pairHalfEdge == nil { return false }
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            heCK = heRT
            repeat {
                r_neighborhood.append(heCK.startVertex)
                if heCK.nextHalfEdge.pairHalfEdge == nil { return false }
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            var cnt: Int = 0
            for l in l_neighborhood {
                for r in r_neighborhood {
                    if l == r { cnt += 1 }
                }
            }
            if cnt >= 3 { return false }
            return true
        }
    }
    
    class Face {
        var uuid: String
        var halfEdge: HalfEdge  //含むハーフエッジの１つ
        struct Status {
            var uuid: String
        }
        init(halfEdge h: HalfEdge) {
            uuid = NSUUID().uuidString
            halfEdge = h
            var he = halfEdge
            repeat {
                he.faceStatus = Status(uuid: self.uuid)
                he = he.nextHalfEdge
            } while he !== halfEdge
        }
        var equation: float4 {
            let v0 = halfEdge.vertex
            let v1 = halfEdge.nextHalfEdge.vertex
            let v2 = halfEdge.prevHalfEdge.vertex
            let c = cross(v1 - v0, v2 - v0)
            let d = -1 * dot(v0, c)
            return float4(c.x, c.y, c.z, d)
        }
        func distanceBy(point: float3) -> Double {
            return Double(dot(self.equation, point.toFloat4))
        }
    }
    
    class Model {
        var faces: [String: Face]
        var fullEdges: [String: FullEdge]
        init() {
            faces = [String: Face]()
            fullEdges = [String: FullEdge]()
        }
        private func setPair(halfEdges targetHalfEdges: HalfEdge...) { //ペアのハーフエッジを設定する
            for targetHalfEdge in targetHalfEdges {
                var flag: Bool = false
                for (_, fullEdge) in fullEdges {
                    if fullEdge.startVertex == targetHalfEdge.endVertex && fullEdge.endVertex == targetHalfEdge.startVertex {
                        fullEdge.set(right: targetHalfEdge)
                        flag = true
                        break
                    }
                }
                if flag == false {
                    let fe = FullEdge(left: targetHalfEdge)
                    fullEdges[fe.uuid] = fe
                }
            }
        }
        func addFace(vertex0: float3, vertex1: float3, vertex2: float3) {
            print("add face")
            let he0 = HalfEdge(vertex: vertex0)
            let he1 = HalfEdge(vertex: vertex1)
            let he2 = HalfEdge(vertex: vertex2)
            he0.setHalfEdge(next: he1, prev: he2)
            he1.setHalfEdge(next: he2, prev: he0)
            he2.setHalfEdge(next: he0, prev: he1)
            let face = Face(halfEdge: he0)
            faces[face.uuid] = face
            setPair(halfEdges: he0, he1, he2)
        }
        func updateQuadraticErrorMetricsAll() {
            for (_, fullEdge) in fullEdges {
                fullEdge.updateQuadraticErrorMetrics(faces: &faces)
            }
        }
        func updateQuadraticErrorMetrics(uuids: [String]) {
            for uuid in uuids {
                if let f = fullEdges[uuid] {
                    f.updateQuadraticErrorMetrics(faces: &faces)
                }
            }
        }
        
        func collapse(fullEdge: FullEdge) {
            print("edgeCollapse")
            if fullEdge.isAbleToCollapse == false {
                fullEdge.quadraticErrorMetrics = Double.infinity
                return
            }
            guard let leftHalfEdge = fullEdge.leftHalfEdge,
                let rightHalfEdge = fullEdge.rightHalfEdge  else { return }
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge,
                let heLB = rightHalfEdge.nextHalfEdge.pairHalfEdge,
                let heRB = rightHalfEdge.prevHalfEdge.pairHalfEdge else { return }
            var heCK: HalfEdge
            var updatedHalfEdge = [String]()
            heCK = heLT
            repeat {
                heCK.startVertex = fullEdge.candidateNewVertex
                updatedHalfEdge.append(heCK.fullEdgeStatus.uuid)
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== fullEdge.leftHalfEdge
            heCK = heRT
            repeat {
                heCK.endVertex = fullEdge.candidateNewVertex
                updatedHalfEdge.append(heCK.fullEdgeStatus.uuid)
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== fullEdge.leftHalfEdge
            
            func deleteFullEdges(uuids: String...) {
                for id in uuids {
                    fullEdges.removeValue(forKey: id)
                    updatedHalfEdge.remove(value: id)
                }
            }
            deleteFullEdges(uuids: fullEdge.uuid, heRT.fullEdgeStatus.uuid, heLT.fullEdgeStatus.uuid,
                            heLB.fullEdgeStatus.uuid, heRB.fullEdgeStatus.uuid)
            
            let fe0 = FullEdge(left: heRT, right: heLT)
            let fe1 = FullEdge(left: heLB, right: heRB)
            fullEdges[fe0.uuid] = fe0
            fullEdges[fe1.uuid] = fe1
            
            updatedHalfEdge.append(fe0.uuid)
            updatedHalfEdge.append(fe1.uuid)
            
            faces.removeValue(forKey: leftHalfEdge.faceStatus.uuid)
            faces.removeValue(forKey: rightHalfEdge.faceStatus.uuid)
            
            self.updateQuadraticErrorMetrics(uuids: updatedHalfEdge.unique)
            return
        }
        func polygonReduction(count: Int) {
            for _ in 0..<(count / 2) {
                let v = fullEdges.min(by: {a, b in a.value.quadraticErrorMetrics < b.value.quadraticErrorMetrics} )
                if let f = v?.value {
                    collapse(fullEdge: f)
                }
            }
        }
    }
    
    static func LoadModel(mtlEz: MetalEz, name: String, reduction: Int) -> Model {
        print("load model")
        let model = Model()
        let bodyVtx = mtlEz.loader.loadMesh(name: name).vertexBuffers[0].buffer
        let pOriBuffer = bodyVtx.contents().assumingMemoryBound(to: MeshPoint.self)
        let vertexCount:Int = bodyVtx.length / MemoryLayout<MeshPoint>.size
        print("set half edge", vertexCount)
        for i in 0..<(vertexCount/3) {
            let v0 = pOriBuffer.advanced(by: i * 3 + 0).pointee.point
            var v1 = pOriBuffer.advanced(by: i * 3 + 1).pointee.point
            var v2 = pOriBuffer.advanced(by: i * 3 + 2).pointee.point
            //            print("point is ", v0, v1, v2)
            let mynm = cross(float3(v1.x - v0.x, v1.y - v0.y, v1.z - v0.z), float3(v2.x - v0.x, v2.y - v0.y, v2.z - v0.z))
            let ptnm = pOriBuffer.advanced(by: i * 3 + 0).pointee.normal
            let asnm = dot(float3(ptnm.x, ptnm.y, ptnm.z), mynm)
            if asnm < 0 {
                print("chenge vertex")
                let myv = v1
                v1 = v2
                v2 = myv
            }
            model.addFace(vertex0: float3(v0.x, v0.y, v0.z), vertex1: float3(v1.x, v1.y, v1.z), vertex2: float3(v2.x, v2.y, v2.z))
        }
        print("update qem all")
        model.updateQuadraticErrorMetricsAll()
        print("reductioning")
        model.polygonReduction(count: reduction)
        return model
    }
    
}

extension Array where Element: Equatable {
    var unique: [Element] {
        return reduce([Element]()) { $0.contains($1) ? $0 : $0 + [$1] }
    }
    mutating func remove(value: Element) {
        if let i = self.index(of: value) {
            self.remove(at: i)
        }
    }
}


*/



/*

class HalfEdgeController {
    class HalfEdge {
        var vertex: float3 //始点となる頂点
        var nextHalfEdge: HalfEdge! //次のハーフエッジ
        var prevHalfEdge: HalfEdge! //前のハーフエッジ
        var pairHalfEdge: HalfEdge? //稜線を挟んで反対側のハーフエッジ
        var fullEdgeStatus: FullEdge.Status!
        var faceStatus: Face.Status!
        init(vertex v: float3) {
            vertex = v
        }
        var endVertex: float3 {
            get { return nextHalfEdge.vertex }
            set(v) { nextHalfEdge.vertex = v }
        }
        var startVertex: float3 {
            get { return vertex }
            set(v) { vertex = v }
        }
        func setHalfEdge(next: HalfEdge, prev: HalfEdge) {
            prevHalfEdge = prev
            nextHalfEdge = next
        }
    }
    class FullEdge {
        var uuid: String
        var leftHalfEdge: HalfEdge! //順方向のハーフエッジ
        var rightHalfEdge: HalfEdge?    //逆方向のハーフエッジ
        var quadraticErrorMetrics: Double = 0.0
        var candidateNewVertex = float3(0, 0, 0)
        init(left: HalfEdge, right: HalfEdge? = nil) {
            uuid = NSUUID().uuidString
            set(left: left)
            if let right = right {
                set(right: right)
                setPairsEachOther()
            }
        }
        func set(left: HalfEdge) {
            leftHalfEdge = left
            left.fullEdgeStatus = Status(uuid: self.uuid, side: .left)
            if rightHalfEdge != nil {
                setPairsEachOther()
            }
        }
        func set(right: HalfEdge) {
            rightHalfEdge = right
            right.fullEdgeStatus = Status(uuid: self.uuid, side: .right)
            setPairsEachOther()
        }
        func setPairsEachOther() {
            leftHalfEdge.pairHalfEdge = rightHalfEdge
            rightHalfEdge?.pairHalfEdge = leftHalfEdge
        }
        var startVertex: float3 {
            return leftHalfEdge.startVertex
        }
        var endVertex: float3 {
            return leftHalfEdge.endVertex
        }
        struct Status {
            enum Side {
                case right
                case left
            }
            var uuid: String
            var side: Side
        }
        func updateQuadraticErrorMetrics(faces: inout [String: Face]) {
            quadraticErrorMetrics = 0
            if self.isAbleToCollapse == false {
                quadraticErrorMetrics = Double.infinity
                return
            }
            var updateFaceID = [String: Bool]()
            guard let leftHalfEdge = self.leftHalfEdge else { return }
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge else { return }
            var heCK: HalfEdge
            heCK = heLT
            repeat {
                updateFaceID[heCK.faceStatus.uuid] = true
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            heCK = heRT
            repeat {
                updateFaceID[heCK.faceStatus.uuid] = true
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            candidateNewVertex = (self.startVertex + self.endVertex) * 0.5
            for (key, _) in updateFaceID {
                if let f = faces[key] {
                    quadraticErrorMetrics += pow(f.distanceBy(point: candidateNewVertex), 2)
                }
            }
        }
        var isAbleToCollapse: Bool {
            guard let leftHalfEdge = self.leftHalfEdge else { return false }
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge else { return false }
            var l_neighborhood = [float3]()
            var r_neighborhood = [float3]()
            var heCK: HalfEdge
            heCK = heLT
            repeat {
                l_neighborhood.append(heCK.endVertex)
                if heCK.prevHalfEdge.pairHalfEdge == nil { return false }
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            heCK = heRT
            repeat {
                r_neighborhood.append(heCK.startVertex)
                if heCK.nextHalfEdge.pairHalfEdge == nil { return false }
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            var cnt: Int = 0
            for l in l_neighborhood {
                for r in r_neighborhood {
                    if l == r { cnt += 1 }
                }
            }
            if cnt >= 3 { return false }
            return true
        }
    }
    
    class Face {
        var uuid: String
        var halfEdge: HalfEdge  //含むハーフエッジの１つ
        struct Status {
            var uuid: String
        }
        init(halfEdge h: HalfEdge) {
            uuid = NSUUID().uuidString
            halfEdge = h
            var he = halfEdge
            repeat {
                he.faceStatus = Status(uuid: self.uuid)
                he = he.nextHalfEdge
            } while he !== halfEdge
        }
        var equation: float4 {
            let v0 = halfEdge.vertex
            let v1 = halfEdge.nextHalfEdge.vertex
            let v2 = halfEdge.prevHalfEdge.vertex
            let c = cross(v1 - v0, v2 - v0)
            let d = -1 * dot(v0, c)
            return float4(c.x, c.y, c.z, d)
        }
        func distanceBy(point: float3) -> Double {
            return Double(dot(self.equation, point.toFloat4))
        }
    }
    
    class Model {
        var faces: [String: Face]
        var fullEdges: [String: FullEdge]
        init() {
            faces = [String: Face]()
            fullEdges = [String: FullEdge]()
        }
        private func setPair(halfEdge targetHalfEdge: HalfEdge) { //ペアのハーフエッジを設定する
            for (_, fullEdge) in fullEdges {
                if fullEdge.startVertex == targetHalfEdge.endVertex && fullEdge.endVertex == targetHalfEdge.startVertex {
                    fullEdge.set(right: targetHalfEdge)
                    return
                }
            }
            let fe = FullEdge(left: targetHalfEdge)
            fullEdges[fe.uuid] = fe
        }
        func addFace(vertex0: float3, vertex1: float3, vertex2: float3) {
            print("add face")
            let he0 = HalfEdge(vertex: vertex0)
            let he1 = HalfEdge(vertex: vertex1)
            let he2 = HalfEdge(vertex: vertex2)
            he0.setHalfEdge(next: he1, prev: he2)
            he1.setHalfEdge(next: he2, prev: he0)
            he2.setHalfEdge(next: he0, prev: he1)
            
            let face = Face(halfEdge: he0)
            faces[face.uuid] = face
            
            setPair(halfEdge: he0)
            setPair(halfEdge: he1)
            setPair(halfEdge: he2)
        }
        
        func updateQuadraticErrorMetricsAll() {
            for (_, fullEdge) in fullEdges {
                fullEdge.updateQuadraticErrorMetrics(faces: &faces)
            }
        }
        func updateQuadraticErrorMetrics(uuids: [String]) {
            for uuid in uuids {
                if let f = fullEdges[uuid] {
                    f.updateQuadraticErrorMetrics(faces: &faces)
                }
            }
        }
        
        func collapse(fullEdge: FullEdge) {
            print("edgeCollapse")
            if fullEdge.isAbleToCollapse == false {
                fullEdge.quadraticErrorMetrics = Double.infinity
                return
            }
            guard let leftHalfEdge = fullEdge.leftHalfEdge,
                let rightHalfEdge = fullEdge.rightHalfEdge  else { return }
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge,
                let heLB = rightHalfEdge.nextHalfEdge.pairHalfEdge,
                let heRB = rightHalfEdge.prevHalfEdge.pairHalfEdge else { return }
            var heCK: HalfEdge
            var updatedHalfEdge = [String: Bool]()
            let newVertex = fullEdge.candidateNewVertex
            heCK = heLT
            repeat {
                heCK.startVertex = newVertex
                updatedHalfEdge[heCK.fullEdgeStatus.uuid] = true
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== fullEdge.leftHalfEdge
            heCK = heRT
            repeat {
                heCK.endVertex = newVertex
                updatedHalfEdge[heCK.fullEdgeStatus.uuid] = true
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== fullEdge.leftHalfEdge
            
            func deleteFullEdges(uuids: String...) {
                for id in uuids {
                    fullEdges.removeValue(forKey: id)
                    updatedHalfEdge.removeValue(forKey: id)
                }
            }
            deleteFullEdges(uuids: fullEdge.uuid, heRT.fullEdgeStatus.uuid, heLT.fullEdgeStatus.uuid,
                            heLB.fullEdgeStatus.uuid, heRB.fullEdgeStatus.uuid)
            
            let fe0 = FullEdge(left: heRT, right: heLT)
            let fe1 = FullEdge(left: heLB, right: heRB)
            fullEdges[fe0.uuid] = fe0
            fullEdges[fe1.uuid] = fe1
            
            updatedHalfEdge[fe0.uuid] = true
            updatedHalfEdge[fe1.uuid] = true
            
            faces.removeValue(forKey: leftHalfEdge.faceStatus.uuid)
            faces.removeValue(forKey: rightHalfEdge.faceStatus.uuid)
            
            var ans = [String]()
            for (key, _) in updatedHalfEdge {
                ans.append(key)
            }
            self.updateQuadraticErrorMetrics(uuids: ans)
            return
        }
        func polygonReduction(count: Int) {
            for _ in 0..<(count / 2) {
                let v = fullEdges.min(by: {a, b in a.value.quadraticErrorMetrics < b.value.quadraticErrorMetrics} )
                if let f = v?.value {
                    collapse(fullEdge: f)
                }
            }
        }
    }
    
    static func LoadModel(mtlEz: MetalEz, name: String, reduction: Int) -> Model {
        print("load model")
        let model = Model()
        let bodyVtx = mtlEz.loader.loadMesh(name: name).vertexBuffers[0].buffer
        let pOriBuffer = bodyVtx.contents().assumingMemoryBound(to: MeshPoint.self)
        let vertexCount:Int = bodyVtx.length / MemoryLayout<MeshPoint>.size
        print("set half edge", vertexCount)
        for i in 0..<(vertexCount/3) {
            let v0 = pOriBuffer.advanced(by: i * 3 + 0).pointee.point
            var v1 = pOriBuffer.advanced(by: i * 3 + 1).pointee.point
            var v2 = pOriBuffer.advanced(by: i * 3 + 2).pointee.point
            //            print("point is ", v0, v1, v2)
            let mynm = cross(float3(v1.x - v0.x, v1.y - v0.y, v1.z - v0.z), float3(v2.x - v0.x, v2.y - v0.y, v2.z - v0.z))
            let ptnm = pOriBuffer.advanced(by: i * 3 + 0).pointee.normal
            let asnm = dot(float3(ptnm.x, ptnm.y, ptnm.z), mynm)
            if asnm < 0 {
                print("chenge vertex")
                let myv = v1
                v1 = v2
                v2 = myv
            }
            model.addFace(vertex0: float3(v0.x, v0.y, v0.z), vertex1: float3(v1.x, v1.y, v1.z), vertex2: float3(v2.x, v2.y, v2.z))
        }
        print("update qem all")
        model.updateQuadraticErrorMetricsAll()
        print("reductioning")
        model.polygonReduction(count: reduction)
        return model
    }
    
}



*/



/*
class HalfEdgeController {
    class HalfEdge {
        var vertex: float3 //始点となる頂点
        var nextHalfEdge: HalfEdge! //次のハーフエッジ
        var prevHalfEdge: HalfEdge! //前のハーフエッジ
        var pairHalfEdge: HalfEdge? //稜線を挟んで反対側のハーフエッジ
        var fullEdgeStatus: FullEdge.Status!
        var faceStatus: Face.Status!
        init(vertex v: float3) {
            vertex = v
        }
        var endVertex: float3 {
            get { return nextHalfEdge.vertex }
            set(v) { nextHalfEdge.vertex = v }
        }
        var startVertex: float3 {
            get { return vertex }
            set(v) { vertex = v }
        }
        func setHalfEdge(next: HalfEdge, prev: HalfEdge) {
            prevHalfEdge = prev
            nextHalfEdge = next
        }
    }
    class FullEdge {
        var uuid: String
        var leftHalfEdge: HalfEdge! //順方向のハーフエッジ
        var rightHalfEdge: HalfEdge?    //逆方向のハーフエッジ
        var quadraticErrorMetrics: Double = 0.0
        init(left: HalfEdge, right: HalfEdge? = nil) {
            uuid = NSUUID().uuidString
            set(left: left)
            if let right = right {
                set(right: right)
                setPairsEachOther()
            }
        }
        func set(left: HalfEdge) {
            leftHalfEdge = left
            left.fullEdgeStatus = Status(uuid: self.uuid, side: .left)
            if rightHalfEdge != nil {
                setPairsEachOther()
            }
        }
        func set(right: HalfEdge) {
            rightHalfEdge = right
            right.fullEdgeStatus = Status(uuid: self.uuid, side: .right)
            setPairsEachOther()
        }
        func setPairsEachOther() {
            leftHalfEdge.pairHalfEdge = rightHalfEdge
            rightHalfEdge?.pairHalfEdge = leftHalfEdge
        }
        var startVertex: float3 {
            return leftHalfEdge.startVertex
        }
        var endVertex: float3 {
            return leftHalfEdge.endVertex
        }
        struct Status {
            enum Side {
                case right
                case left
            }
            var uuid: String
            var side: Side
        }
        func updateQuadraticErrorMetrics(faces: inout [String: Face]) {
            quadraticErrorMetrics = 0
            if self.isAbleToCollapse == false {
                quadraticErrorMetrics = Double.infinity
                return
            }
            var updateFaceID = [String: Bool]()
            guard let leftHalfEdge = self.leftHalfEdge else { return }
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge else { return }
            var heCK: HalfEdge
            heCK = heLT
            repeat {
                updateFaceID[heCK.faceStatus.uuid] = true
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            heCK = heRT
            repeat {
                updateFaceID[heCK.faceStatus.uuid] = true
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            let newPoint = (self.startVertex + self.endVertex) * 0.5
            for (key, _) in updateFaceID {
                if let f = faces[key] {
                    quadraticErrorMetrics += pow(f.distanceBy(point: newPoint), 2)
                }
            }
        }
        var isAbleToCollapse: Bool {
            guard let leftHalfEdge = self.leftHalfEdge else { return false }
            
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge else { return false }
            
            var heCK: HalfEdge
            var l_neighborhood = [float3]()
            var r_neighborhood = [float3]()
            heCK = heLT
            repeat {
                l_neighborhood.append(heCK.endVertex)
                if heCK.prevHalfEdge.pairHalfEdge == nil { return false }
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            heCK = heRT
            repeat {
                r_neighborhood.append(heCK.startVertex)
                if heCK.nextHalfEdge.pairHalfEdge == nil { return false }
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== self.leftHalfEdge
            var cnt: Int = 0
            for l in l_neighborhood {
                for r in r_neighborhood {
                    if l == r { cnt += 1 }
                }
            }
            if cnt >= 3 { return false }
            return true
        }
    }
    
    class Face {
        var uuid: String
        var halfEdge: HalfEdge  //含むハーフエッジの１つ
        init(halfEdge h: HalfEdge) {
            uuid = NSUUID().uuidString
            halfEdge = h
            var he = halfEdge
            repeat {
                he.faceStatus = Status(uuid: self.uuid)
                he = he.nextHalfEdge
            } while he !== halfEdge
        }
        var equation: float4 {
            let v0 = halfEdge.vertex
            let v1 = halfEdge.nextHalfEdge.vertex
            let v2 = halfEdge.prevHalfEdge.vertex
            let c = cross(v1 - v0, v2 - v0)
            let d = -1 * dot(v0, c)
            return float4(c.x, c.y, c.z, d)
        }
        struct Status {
            var uuid: String
        }
        func distanceBy(point: float3) -> Double {
            return Double(dot(self.equation, point.toFloat4))
        }
    }
    
    class Model {
        var faces: [String: Face]
        var fullEdges: [String: FullEdge]
        init() {
            faces = [String: Face]()
            fullEdges = [String: FullEdge]()
        }
        private func setPair(halfEdge targetHalfEdge: HalfEdge) { //ペアのハーフエッジを設定する
            for (_, fullEdge) in fullEdges {
                if fullEdge.startVertex == targetHalfEdge.endVertex && fullEdge.endVertex == targetHalfEdge.startVertex {
                    fullEdge.set(right: targetHalfEdge)
                    return
                }
            }
            let fe = FullEdge(left: targetHalfEdge)
            fullEdges[fe.uuid] = fe
        }
        func addFace(vertex0: float3, vertex1: float3, vertex2: float3) {
            print("add face")
            let he0 = HalfEdge(vertex: vertex0)
            let he1 = HalfEdge(vertex: vertex1)
            let he2 = HalfEdge(vertex: vertex2)
            he0.setHalfEdge(next: he1, prev: he2)
            he1.setHalfEdge(next: he2, prev: he0)
            he2.setHalfEdge(next: he0, prev: he1)
            
            let face = Face(halfEdge: he0)
            faces[face.uuid] = face
            
            setPair(halfEdge: he0)
            setPair(halfEdge: he1)
            setPair(halfEdge: he2)
        }
        
        func updateQuadraticErrorMetricsAll() {
            for (_, fullEdge) in fullEdges {
                fullEdge.updateQuadraticErrorMetrics(faces: &faces)
            }
        }
        func updateQuadraticErrorMetrics(uuids: [String]) {
            for uuid in uuids {
                if let f = fullEdges[uuid] {
                    f.updateQuadraticErrorMetrics(faces: &faces)
                }
            }
        }
        
        func collapse(fullEdge: FullEdge) {
            print("edgeCollapse")
            var ans = [String]()
            guard let leftHalfEdge = fullEdge.leftHalfEdge,
                let rightHalfEdge = fullEdge.rightHalfEdge  else { return }
            
            guard let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge,
                let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge,
                let heLB = rightHalfEdge.nextHalfEdge.pairHalfEdge,
                let heRB = rightHalfEdge.prevHalfEdge.pairHalfEdge else { return }
            
            var heCK: HalfEdge
            /*            var l_neighborhood = [float3]()
             var r_neighborhood = [float3]()
             heCK = heLT
             repeat {
             l_neighborhood.append(heCK.endVertex)
             if heCK.prevHalfEdge.pairHalfEdge == nil { return ans }
             heCK = heCK.prevHalfEdge.pairHalfEdge!
             } while heCK !== fullEdge.leftHalfEdge
             heCK = heRT
             repeat {
             r_neighborhood.append(heCK.startVertex)
             if heCK.nextHalfEdge.pairHalfEdge == nil { return ans }
             heCK = heCK.nextHalfEdge.pairHalfEdge!
             } while heCK !== fullEdge.leftHalfEdge
             var cnt: Int = 0
             for l in l_neighborhood {
             for r in r_neighborhood {
             if l == r { cnt += 1 }
             }
             }
             if cnt >= 3 { return ans } */
            
            if fullEdge.isAbleToCollapse == false {
                fullEdge.quadraticErrorMetrics = Double.infinity
                return
            }
            
            var updatedHalfEdge = [String: Bool]()
            
            let newVertex = (fullEdge.startVertex + fullEdge.endVertex) * 0.5
            heCK = heLT
            repeat {
                heCK.startVertex = newVertex
                updatedHalfEdge[heCK.fullEdgeStatus.uuid] = true
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== fullEdge.leftHalfEdge
            heCK = heRT
            repeat {
                heCK.endVertex = newVertex
                updatedHalfEdge[heCK.fullEdgeStatus.uuid] = true
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== fullEdge.leftHalfEdge
            
            fullEdges.removeValue(forKey: fullEdge.uuid)
            fullEdges.removeValue(forKey: heRT.fullEdgeStatus.uuid)
            fullEdges.removeValue(forKey: heLT.fullEdgeStatus.uuid)
            fullEdges.removeValue(forKey: heLB.fullEdgeStatus.uuid)
            fullEdges.removeValue(forKey: heRB.fullEdgeStatus.uuid)
            
            updatedHalfEdge.removeValue(forKey: fullEdge.uuid)
            updatedHalfEdge.removeValue(forKey: heRT.fullEdgeStatus.uuid)
            updatedHalfEdge.removeValue(forKey: heLT.fullEdgeStatus.uuid)
            updatedHalfEdge.removeValue(forKey: heLB.fullEdgeStatus.uuid)
            updatedHalfEdge.removeValue(forKey: heRB.fullEdgeStatus.uuid)
            
            let fe0 = FullEdge(left: heRT, right: heLT)
            let fe1 = FullEdge(left: heLB, right: heRB)
            fullEdges[fe0.uuid] = fe0
            fullEdges[fe1.uuid] = fe1
            
            updatedHalfEdge[fe0.uuid] = true
            updatedHalfEdge[fe1.uuid] = true
            
            faces.removeValue(forKey: leftHalfEdge.faceStatus.uuid)
            faces.removeValue(forKey: rightHalfEdge.faceStatus.uuid)
            
            for (key, _) in updatedHalfEdge {
                ans.append(key)
            }
            self.updateQuadraticErrorMetrics(uuids: ans)
            return
        }
    }
    
    static func LoadModel(mtlEz: MetalEz, name: String, reduction: Int) -> Model {
        print("load model")
        let model = Model()
        let bodyVtx = mtlEz.loader.loadMesh(name: name).vertexBuffers[0].buffer
        let pOriBuffer = bodyVtx.contents().assumingMemoryBound(to: MeshPoint.self)
        let vertexCount:Int = bodyVtx.length / MemoryLayout<MeshPoint>.size
        print("set half edge", vertexCount)
        for i in 0..<(vertexCount/3) {
            let v0 = pOriBuffer.advanced(by: i * 3 + 0).pointee.point
            var v1 = pOriBuffer.advanced(by: i * 3 + 1).pointee.point
            var v2 = pOriBuffer.advanced(by: i * 3 + 2).pointee.point
            print("point is ", v0, v1, v2)
            let mynm = cross(float3(v1.x - v0.x, v1.y - v0.y, v1.z - v0.z), float3(v2.x - v0.x, v2.y - v0.y, v2.z - v0.z))
            let ptnm = pOriBuffer.advanced(by: i * 3 + 0).pointee.normal
            let asnm = dot(float3(ptnm.x, ptnm.y, ptnm.z), mynm)
            if asnm < 0 {
                print("chenge vertex")
                let myv = v1
                v1 = v2
                v2 = myv
            }
            model.addFace(vertex0: float3(v0.x, v0.y, v0.z), vertex1: float3(v1.x, v1.y, v1.z), vertex2: float3(v2.x, v2.y, v2.z))
        }
        print("update qem all")
        model.updateQuadraticErrorMetricsAll()
        print("reductioning")
        for _ in 0..<(reduction / 2) {
            let v = model.fullEdges.min(by: {a, b in a.value.quadraticErrorMetrics < b.value.quadraticErrorMetrics} )
            if let f = v?.value {
                model.collapse(fullEdge: f)
            }
            /*            let tage: Int = Int(Double(model.fullEdges.count) * drand48())
             var cnt: Int = 0
             for (_, fullEdge) in model.fullEdges {
             cnt += 1
             if tage == cnt {
             model.collapse(fullEdge: fullEdge)
             //                    model.updateQuadraticErrorMetrics(uuids: uuids)
             }
             }*/
        }
        return model
    }
    
}
*/




/*


class HalfEdgeController2 {
    class Vertex {
        var position: float3   //頂点座標
        var halfEdge: HalfEdge! = nil   //この頂点を始点に持つハーフエッジの１つ
        init(_ p: float3) {
            position = p
        }
        init(_ p: myfloat3) {
            position = float3(p.x, p.y, p.z)
        }
    }
    
    open class HalfEdge {
        var vertex: Vertex //始点となる頂点
        var face: Face! //このハーフエッジを含む面
        var nextHalfEdge: HalfEdge! //次のハーフエッジ
        var prevHalfEdge: HalfEdge! //前のハーフエッジ
        var pairHalfEdge: HalfEdge? //稜線を挟んで反対側のハーフエッジ
        init(vertex v: Vertex) {
            vertex = v
            if vertex.halfEdge == nil {
                vertex.halfEdge = self
            }
        }
    }
    class FullEdge {
        var startVertex: Vertex!    //始点
        var endVertex: Vertex!  //終点
        var leftHalfEdge: HalfEdge! //順方向のハーフエッジ
        var rightHalfEdge: HalfEdge!    //逆方向のハーフエッジ
        init() {
            
        }
    }
    
    class Face {
        var halfEdge: HalfEdge  //含むハーフエッジの１つ
        init(halfEdge h: HalfEdge) {
            halfEdge = h
        }
    }
    
    class Model {
        var faces: [Face]
        var vertexes: [Vertex]
        init() {
            faces = [Face]()
            vertexes = [Vertex]()
        }
        private func setPair(halfEdge myHE: HalfEdge) { //ペアのハーフエッジを設定する
            for face in faces { //全ての面を探索する
                var checkHE: HalfEdge = face.halfEdge   //チェックするハーフエッジ
                for _ in 0..<3 {
                    if checkHE.vertex.position == myHE.nextHalfEdge.vertex.position &&
                        myHE.vertex.position == checkHE.nextHalfEdge.vertex.position {   //もしもペアだったら
                        print("this is pair")
                        checkHE.pairHalfEdge = myHE
                        myHE.pairHalfEdge = checkHE
                        return  //お互いを設定して終了
                    }
                    checkHE = checkHE.nextHalfEdge  //次のハーフエッジ
                }
            }
        }
        func addFace(vertex0: Vertex, vertex1: Vertex, vertex2: Vertex) {
            print("add face")
            let he0 = HalfEdge(vertex: vertex0)
            let he1 = HalfEdge(vertex: vertex1)
            let he2 = HalfEdge(vertex: vertex2)
            
            he0.nextHalfEdge = he1
            he0.prevHalfEdge = he2
            he1.nextHalfEdge = he2
            he1.prevHalfEdge = he0
            he2.nextHalfEdge = he0
            he2.prevHalfEdge = he1
            
            let face = Face(halfEdge: he0)
            he0.face = face
            he1.face = face
            he2.face = face

            faces.append(face)
            
            setPair(halfEdge: he0)
            setPair(halfEdge: he1)
            setPair(halfEdge: he2)
        }
        
        
        
        
        func setPairs(h0: HalfEdge, h1: HalfEdge) {
            h0.pairHalfEdge = h1
            h1.pairHalfEdge = h0
        }
        
        func delete(vertex: Vertex) {
            //remove vertex
        }
        func delete(face: Face) {
            //remove face
            //delete face.halfedge, face.halfedge.next, face.halfedge.prev
        }
        
        func edgeCollapse(halfEdge he: HalfEdge) {
            print("edgeCollapse")
            let heLT = he.prevHalfEdge.pairHalfEdge!
            let heRT = he.nextHalfEdge.pairHalfEdge!
            let heLB = (he.pairHalfEdge?.nextHalfEdge.pairHalfEdge)!
            let heRB = (he.pairHalfEdge?.prevHalfEdge.pairHalfEdge)!
            
            print("hello")
            he.nextHalfEdge.vertex.position = (he.vertex.position + he.nextHalfEdge.vertex.position) * 0.5
            he.nextHalfEdge.vertex.halfEdge = heRB
            he.prevHalfEdge.vertex.halfEdge = heRT
            he.pairHalfEdge?.prevHalfEdge.vertex.halfEdge = heLB
            
            print("hello")
            let newVertex = he.nextHalfEdge.vertex
            var heCK = he.prevHalfEdge.pairHalfEdge!
            repeat {
                heCK.vertex = newVertex
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== he
/*            while heCK !== he.pairHalfEdge?.nextHalfEdge! {
                heCK.vertex = newVertex
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            }*/
            print("hello")
            heCK = he.nextHalfEdge.pairHalfEdge!
            repeat {
                heCK.nextHalfEdge.vertex = newVertex
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== he
//            while heCK !== he.pairHalfEdge?.prevHalfEdge! {
//            }
            
            
            
            setPairs(h0: heRT, h1: heLT)
            setPairs(h0: heLB, h1: heRB)
            
            print("hello")
            delete(vertex: he.vertex)
            var cnt: Int = 0
            var he_face_count: Int = -1
            var pr_face_count: Int = -1
            for face in faces {
                if face === he.face {
                    he_face_count = cnt
                }
                cnt += 1
            }
            faces.remove(at: he_face_count)
            cnt = 0
            for face in faces {
                if face === he.pairHalfEdge!.face {
                    pr_face_count = cnt
                }
                cnt += 1
            }
            faces.remove(at: pr_face_count)

            delete(face: he.pairHalfEdge!.face)
            delete(face: he.face)
        }
        
    }
    
    static func LoadModel(mtlEz: MetalEz, name: String, reduction: Int) -> Model {
        print("load model")
        let model = Model()
        let bodyVtx = mtlEz.loader.loadMesh(name: name).vertexBuffers[0].buffer
        let pOriBuffer = bodyVtx.contents().assumingMemoryBound(to: MeshPoint.self)
        let vertexCount:Int = bodyVtx.length / MemoryLayout<MeshPoint>.size
        print("set half edge", vertexCount)
        for i in 0..<(vertexCount/3) {
//        for i in 0..<12 {
            let v0 = pOriBuffer.advanced(by: i * 3 + 0).pointee.point
            var v1 = pOriBuffer.advanced(by: i * 3 + 1).pointee.point
            var v2 = pOriBuffer.advanced(by: i * 3 + 2).pointee.point
            print("point is ", v0, v1, v2)
            let mynm = cross(float3(v1.x - v0.x, v1.y - v0.y, v1.z - v0.z), float3(v2.x - v0.x, v2.y - v0.y, v2.z - v0.z))
            let ptnm = pOriBuffer.advanced(by: i * 3 + 0).pointee.normal
            let asnm = dot(float3(ptnm.x, ptnm.y, ptnm.z), mynm)
            if asnm < 0 {
                print("chenge vertex")
                let myv = v1
                v1 = v2
                v2 = myv
            }
            model.addFace(vertex0: Vertex(v0), vertex1: Vertex(v1), vertex2: Vertex(v2))
        }
        
        print("reductioning")
        for _ in 0..<reduction {
            let tage: Int = Int(Double(model.faces.count) * drand48())
            model.edgeCollapse(halfEdge: model.faces[tage].halfEdge )
//            model.faces.remove(at: tage)
        }
        
//        model.edgeCollapse(halfEdge: model.faces[50].halfEdge )
//        model.faces.remove(at: 50)
        
//        model.edgeCollapse(halfEdge: model.faces[101].halfEdge.nextHalfEdge )
//        model.faces.remove(at: 101)
        
        return model
    }
    
}
*/



/*
extension HalfEdgeController2 {
    struct myfloat4 {
        var x: Float
        var y: Float
        var z: Float
        var w: Float
    }
    struct myfloat3 {
        var x: Float
        var y: Float
        var z: Float
    }
    struct myfloat2 {
        var x: Float
        var y: Float
    }
    struct MeshPoint {
        var point: myfloat3
        var normal: myfloat3
        var texcoord: myfloat2
    }
}
*/


/*
class HalfEdgeController {
    open class HalfEdge {
        var vertex: float3 //始点となる頂点
        //        var face: Face! //このハーフエッジを含む面
        var nextHalfEdge: HalfEdge! //次のハーフエッジ
        var prevHalfEdge: HalfEdge! //前のハーフエッジ
        var pairHalfEdge: HalfEdge? //稜線を挟んで反対側のハーフエッジ
        var fullEdgeStatus: FullEdge.Status!
        var faceStatus: Face.Status!
        init(vertex v: float3) {
            vertex = v
        }
        var endVertex: float3 {
            get { return nextHalfEdge.vertex }
            set(v) { nextHalfEdge.vertex = v }
        }
        var startVertex: float3 {
            get { return vertex }
            set(v) { vertex = v }
        }
        func setHalfEdge(next: HalfEdge, prev: HalfEdge) {
            prevHalfEdge = prev
            nextHalfEdge = next
        }
    }
    class FullEdge {
        var uuid: String
        var leftHalfEdge: HalfEdge! //順方向のハーフエッジ
        var rightHalfEdge: HalfEdge?    //逆方向のハーフエッジ
        init(left: HalfEdge, right: HalfEdge? = nil) {
            uuid = NSUUID().uuidString
            set(left: left)
            if let right = right {
                set(right: right)
                setPairsEachOther()
            }
        }
        func set(left: HalfEdge) {
            leftHalfEdge = left
            left.fullEdgeStatus = Status(uuid: self.uuid, side: .left)
            if rightHalfEdge != nil {
                setPairsEachOther()
            }
        }
        func set(right: HalfEdge) {
            rightHalfEdge = right
            right.fullEdgeStatus = Status(uuid: self.uuid, side: .right)
            setPairsEachOther()
        }
        func setPairsEachOther() {
            leftHalfEdge.pairHalfEdge = rightHalfEdge
            rightHalfEdge?.pairHalfEdge = leftHalfEdge
        }
        var startVertex: float3 {
            return leftHalfEdge.startVertex
        }
        var endVertex: float3 {
            return leftHalfEdge.endVertex
        }
        struct Status {
            enum Side {
                case right
                case left
            }
            var uuid: String
            var side: Side
        }
    }
    
    class Face {
        var uuid: String
        var halfEdge: HalfEdge  //含むハーフエッジの１つ
        init(halfEdge h: HalfEdge) {
            uuid = NSUUID().uuidString
            halfEdge = h
            var he = halfEdge
            repeat {
                he.faceStatus = Status(uuid: self.uuid)
                he = he.nextHalfEdge
            } while he !== halfEdge
        }
        struct Status {
            var uuid: String
        }
    }
    
    class Model {
        var faces: [String: Face]
        var fullEdges: [String: FullEdge]
        init() {
            faces = [String: Face]()
            fullEdges = [String: FullEdge]()
        }
        private func setPair(halfEdge targetHalfEdge: HalfEdge) { //ペアのハーフエッジを設定する
            for (_, fullEdge) in fullEdges {
                if fullEdge.startVertex == targetHalfEdge.endVertex && fullEdge.endVertex == targetHalfEdge.startVertex {
                    fullEdge.set(right: targetHalfEdge)
                    return
                }
            }
            let fe = FullEdge(left: targetHalfEdge)
            fullEdges[fe.uuid] = fe
        }
        func addFace(vertex0: float3, vertex1: float3, vertex2: float3) {
            print("add face")
            let he0 = HalfEdge(vertex: vertex0)
            let he1 = HalfEdge(vertex: vertex1)
            let he2 = HalfEdge(vertex: vertex2)
            
            //            he0.nextHalfEdge = he1
            //            he0.prevHalfEdge = he2
            he0.setHalfEdge(next: he1, prev: he2)
            //            he1.nextHalfEdge = he2
            //            he1.prevHalfEdge = he0
            he1.setHalfEdge(next: he2, prev: he0)
            //            he2.nextHalfEdge = he0
            //            he2.prevHalfEdge = he1
            he2.setHalfEdge(next: he0, prev: he1)
            
            let face = Face(halfEdge: he0)
            faces[face.uuid] = face
            
            setPair(halfEdge: he0)
            setPair(halfEdge: he1)
            setPair(halfEdge: he2)
        }
        
        func collapse(fullEdge: FullEdge) {
            print("edgeCollapse")
            guard let leftHalfEdge = fullEdge.leftHalfEdge, let rightHalfEdge = fullEdge.rightHalfEdge  else {
                return
            }
            var heCK: HalfEdge
            let heLT = leftHalfEdge.prevHalfEdge.pairHalfEdge!
            let heRT = leftHalfEdge.nextHalfEdge.pairHalfEdge!
            let heLB = rightHalfEdge.nextHalfEdge.pairHalfEdge!
            let heRB = rightHalfEdge.prevHalfEdge.pairHalfEdge!
            
            var l_neighborhood = [float3]()
            var r_neighborhood = [float3]()
            heCK = heLT
            repeat {
                l_neighborhood.append(heCK.endVertex)
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== fullEdge.leftHalfEdge
            heCK = heRT
            repeat {
                r_neighborhood.append(heCK.startVertex)
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== fullEdge.leftHalfEdge
            var cnt: Int = 0
            for l in l_neighborhood {
                for r in r_neighborhood {
                    if l == r {
                        cnt += 1
                    }
                }
            }
            if cnt > 3 {
                return
            }
            
            
            let newVertex = (fullEdge.startVertex + fullEdge.endVertex) * 0.5
            heCK = heLT
            repeat {
                //                heCK.vertex = newVertex
                heCK.startVertex = newVertex
                heCK = heCK.prevHalfEdge.pairHalfEdge!
            } while heCK !== fullEdge.leftHalfEdge
            heCK = heRT
            repeat {
                //                heCK.nextHalfEdge.vertex = newVertex
                heCK.endVertex = newVertex
                heCK = heCK.nextHalfEdge.pairHalfEdge!
            } while heCK !== fullEdge.leftHalfEdge
            
            fullEdges.removeValue(forKey: fullEdge.uuid)
            fullEdges.removeValue(forKey: heRT.fullEdgeStatus.uuid)
            fullEdges.removeValue(forKey: heLT.fullEdgeStatus.uuid)
            fullEdges.removeValue(forKey: heLB.fullEdgeStatus.uuid)
            fullEdges.removeValue(forKey: heRB.fullEdgeStatus.uuid)
            
            let fe0 = FullEdge(left: heRT, right: heLT)
            let fe1 = FullEdge(left: heLB, right: heRB)
            fullEdges[fe0.uuid] = fe0
            fullEdges[fe1.uuid] = fe1
            
            faces.removeValue(forKey: leftHalfEdge.faceStatus.uuid)
            faces.removeValue(forKey: rightHalfEdge.faceStatus.uuid)
        }
        
    }
    
    static func LoadModel(mtlEz: MetalEz, name: String, reduction: Int) -> Model {
        print("load model")
        let model = Model()
        let bodyVtx = mtlEz.loader.loadMesh(name: name).vertexBuffers[0].buffer
        let pOriBuffer = bodyVtx.contents().assumingMemoryBound(to: MeshPoint.self)
        let vertexCount:Int = bodyVtx.length / MemoryLayout<MeshPoint>.size
        print("set half edge", vertexCount)
        for i in 0..<(vertexCount/3) {
            let v0 = pOriBuffer.advanced(by: i * 3 + 0).pointee.point
            var v1 = pOriBuffer.advanced(by: i * 3 + 1).pointee.point
            var v2 = pOriBuffer.advanced(by: i * 3 + 2).pointee.point
            print("point is ", v0, v1, v2)
            let mynm = cross(float3(v1.x - v0.x, v1.y - v0.y, v1.z - v0.z), float3(v2.x - v0.x, v2.y - v0.y, v2.z - v0.z))
            let ptnm = pOriBuffer.advanced(by: i * 3 + 0).pointee.normal
            let asnm = dot(float3(ptnm.x, ptnm.y, ptnm.z), mynm)
            if asnm < 0 {
                print("chenge vertex")
                let myv = v1
                v1 = v2
                v2 = myv
            }
            model.addFace(vertex0: float3(v0.x, v0.y, v0.z), vertex1: float3(v1.x, v1.y, v1.z), vertex2: float3(v2.x, v2.y, v2.z))
        }
        
        print("reductioning")
        for _ in 0..<reduction {
            let tage: Int = Int(Double(model.fullEdges.count) * drand48())
            var cnt: Int = 0
            for (_, fullEdge) in model.fullEdges {
                cnt += 1
                if tage == cnt {
                    model.collapse(fullEdge: fullEdge)
                }
            }
        }
        return model
    }
    
}
*/






//class PolygonReduction {
    
    
    /*
    
    static func makeSkinningVertexBuffer(mtlEz: MetalEz, originalVertexBuffer: inout MTLBuffer, rootBone root: Bone) -> MTLBuffer {
        let c:Float = 16
        var boneArray = [Bone]()
        root.setBoneArray(array: &boneArray)
        boneArray.forEach {
            $0.printData()
        }
        let pOriBuffer = originalVertexBuffer.contents().assumingMemoryBound(to: MeshPoint.self)
        
        let vertexCount:Int = originalVertexBuffer.length / MemoryLayout<MeshPoint>.size
        let ansBuffer = mtlEz.device.makeBuffer(length: MemoryLayout<MeshSkininghPoint>.size * vertexCount, options: [])
        let pAnsBuffer = ansBuffer?.contents().assumingMemoryBound(to: MeshSkininghPoint.self)
        
        for j in 0..<vertexCount {
            pAnsBuffer?.advanced(by: j).pointee.point = pOriBuffer.advanced(by: j).pointee.point
            //            pAnsBuffer?.advanced(by: j).pointee.point.x *= 0.01
            //            pAnsBuffer?.advanced(by: j).pointee.point.y *= 0.01
            //            pAnsBuffer?.advanced(by: j).pointee.point.z *= 0.01
            
            pAnsBuffer?.advanced(by: j).pointee.normal = pOriBuffer.advanced(by: j).pointee.normal
            pAnsBuffer?.advanced(by: j).pointee.texcoord = pOriBuffer.advanced(by: j).pointee.texcoord
            
            let x = pAnsBuffer?.advanced(by: j).pointee.point.x
            let y = pAnsBuffer?.advanced(by: j).pointee.point.y
            let z = pAnsBuffer?.advanced(by: j).pointee.point.z
            for i in 0..<boneArray.count {
                boneArray[i].calcDistanceByPoint(point: float3(x!, y!, z!))
            }
            
            var num1 = 0
            var shortBone1 = boneArray[num1]
            for i in num1+1..<boneArray.count {
                if shortBone1.distance > boneArray[i].distance {
                    shortBone1 = boneArray[i]
                    num1 = i
                }
            }
            var num2 = 0
            if num1 == 0 { num2 = 1 }
            var shortBone2 = boneArray[num2]
            for i in num2+1..<boneArray.count {
                if i == num1 { continue }
                if shortBone2.distance > boneArray[i].distance {
                    shortBone2 = boneArray[i]
                    num2 = i
                }
            }
            let wd1 = 1.0/pow(shortBone1.distance + 0.01, c)
            let wd2 = 1.0/pow(shortBone2.distance + 0.01, c)
            let add = wd1 + wd2
            let w1 = wd1 / add
            let w2 = wd2 / add
            pAnsBuffer?.advanced(by: j).pointee.param = myfloat4(x: Float(num1), y: w1, z: Float(num2), w: w2)
        }
        return ansBuffer!
    }
 */
//}







